import Foundation
import CZlib

public indirect enum NBTValue: Sendable, Equatable {
    case integer(Int64), decimal(Double), string(String), compound([String: NBTValue]), list([NBTValue]), array(Data)
    public var integer: Int64? { if case .integer(let value) = self { value } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public subscript(_ key: String) -> NBTValue? { if case .compound(let value) = self { value[key] } else { nil } }
}

public enum Gzip {
    public static func decompress(_ data: Data, limit: Int = 32 * 1024 * 1024) throws -> Data {
        guard data.count <= 32 * 1024 * 1024 else { throw RuriError.message("压缩 NBT 文件过大") }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw RuriError.message("无法初始化 gzip 解压") }
        defer { inflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var output = Data(); var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                try Task.checkCancellation()
                let status = buffer.withUnsafeMutableBytes { bytes -> Int32 in
                    stream.next_out = bytes.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(bytes.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let written = buffer.count - Int(stream.avail_out)
                guard written <= limit - output.count else { throw RuriError.message("NBT 解压大小超出限制") }
                output.append(contentsOf: buffer.prefix(written))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw RuriError.message("gzip 文件包含多余数据") }
                    return output
                }
                guard status == Z_OK, written > 0 || stream.avail_in > 0 else { throw RuriError.message("gzip 文件损坏或校验失败") }
            }
        }
    }
}

public struct NBTReader {
    private var bytes: [UInt8]
    private var offset = 0
    private var remainingTags = 200_000
    public init(data: Data) throws {
        let decoded = data.starts(with: [0x1f, 0x8b]) ? try Gzip.decompress(data) : data
        guard decoded.count <= 32 * 1024 * 1024 else { throw RuriError.message("NBT 文件过大") }
        bytes = Array(decoded)
    }
    public mutating func read() throws -> NBTValue {
        guard try byte() == 10 else { throw RuriError.message("NBT 根节点不是复合标签") }
        _ = try text()
        let value = try payload(10, depth: 0)
        guard offset == bytes.count else { throw RuriError.message("NBT 根节点后有多余数据") }
        return value
    }
    private mutating func payload(_ tag: UInt8, depth: Int) throws -> NBTValue {
        remainingTags -= 1
        guard remainingTags >= 0, depth <= 64 else { throw RuriError.message("NBT 结构超出限制") }
        switch tag {
        case 1: return .integer(Int64(Int8(bitPattern: try byte())))
        case 2: return .integer(Int64(Int16(bitPattern: UInt16(try unsigned(2)))))
        case 3: return .integer(Int64(Int32(bitPattern: UInt32(try unsigned(4)))))
        case 4: return .integer(Int64(bitPattern: try unsigned(8)))
        case 5: return .decimal(Double(Float(bitPattern: UInt32(try unsigned(4)))))
        case 6: return .decimal(Double(bitPattern: try unsigned(8)))
        case 7, 11, 12:
            let count = try count()
            let width = tag == 7 ? 1 : tag == 11 ? 4 : 8
            guard count <= (bytes.count - offset) / width else { throw RuriError.message("NBT 数组越界") }
            let length = count * width; defer { offset += length }
            return .array(Data(bytes[offset..<(offset + length)]))
        case 8: return .string(try text())
        case 9:
            let subtype = try byte(); let count = try count()
            guard count <= remainingTags, count == 0 || (1...12).contains(subtype) else { throw RuriError.message("NBT 列表无效") }
            var values: [NBTValue] = []; values.reserveCapacity(count)
            for _ in 0..<count { values.append(try payload(subtype, depth: depth + 1)) }
            return .list(values)
        case 10:
            var value: [String: NBTValue] = [:]
            while true {
                let type = try byte()
                if type == 0 { break }
                let key = try text()
                guard value[key] == nil else { throw RuriError.message("NBT 包含重复标签") }
                value[key] = try payload(type, depth: depth + 1)
            }
            return .compound(value)
        default: throw RuriError.message("未知 NBT 标签：\(tag)")
        }
    }
    private mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw RuriError.message("NBT 文件被截断") }
        defer { offset += 1 }; return bytes[offset]
    }
    private mutating func unsigned(_ count: Int) throws -> UInt64 {
        guard count <= bytes.count - offset else { throw RuriError.message("NBT 数值越界") }
        var value: UInt64 = 0
        for _ in 0..<count { value = (value << 8) | UInt64(try byte()) }
        return value
    }
    private mutating func count() throws -> Int {
        let value = Int32(bitPattern: UInt32(try unsigned(4)))
        guard value >= 0 else { throw RuriError.message("NBT 数组长度为负") }; return Int(value)
    }
    private mutating func text() throws -> String {
        let length = Int(try unsigned(2))
        guard length <= bytes.count - offset else { throw RuriError.message("NBT 字符串越界") }
        let data = Data(bytes[offset..<(offset + length)]); offset += length
        if let result = String(data: data, encoding: .utf8) { return result }
        // Java NBT strings use modified UTF-8, including CESU-8 surrogate pairs.
        let input = Array(data); var units: [UInt16] = []; var i = 0
        while i < input.count {
            let a = input[i]; i += 1
            if a < 0x80 { units.append(UInt16(a)) }
            else if a & 0xe0 == 0xc0 {
                guard i < input.count, input[i] & 0xc0 == 0x80 else { throw RuriError.message("NBT 字符编码无效") }
                units.append(UInt16(a & 0x1f) << 6 | UInt16(input[i] & 0x3f)); i += 1
            } else if a & 0xf0 == 0xe0 {
                guard i + 1 < input.count, input[i] & 0xc0 == 0x80, input[i + 1] & 0xc0 == 0x80 else { throw RuriError.message("NBT 字符编码无效") }
                units.append(UInt16(a & 0x0f) << 12 | UInt16(input[i] & 0x3f) << 6 | UInt16(input[i + 1] & 0x3f)); i += 2
            } else { throw RuriError.message("NBT 字符编码无效") }
        }
        return String(decoding: units, as: UTF16.self)
    }
}
