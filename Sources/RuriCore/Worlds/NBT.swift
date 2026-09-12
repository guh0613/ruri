import RuriLocalization
import Foundation
import CZlib

public indirect enum NBTValue: Sendable, Equatable {
    case integer(Int64), decimal(Double), string(String), compound([String: NBTValue]), list([NBTValue]), array(Data)
    public var integer: Int64? { if case .integer(let value) = self { value } else { nil } }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public subscript(_ key: String) -> NBTValue? { if case .compound(let value) = self { value[key] } else { nil } }
}

public enum Gzip {
    static func compress(_ data: Data) throws -> Data {
        guard data.count <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreNBT.compressText1) }
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw RuriError.message(Messages.CoreNBT.streamText1) }
        defer { deflateEnd(&stream) }
        return try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var output = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let status = buffer.withUnsafeMutableBytes { bytes -> Int32 in
                    stream.next_out = bytes.bindMemory(to: UInt8.self).baseAddress
                    stream.avail_out = uInt(bytes.count)
                    return deflate(&stream, Z_FINISH)
                }
                output.append(contentsOf: buffer.prefix(buffer.count - Int(stream.avail_out)))
                if status == Z_STREAM_END { return output }
                guard status == Z_OK else { throw RuriError.message(Messages.CoreNBT.statusText1) }
            }
        }
    }
    public static func decompress(_ data: Data, limit: Int = 32 * 1024 * 1024) throws -> Data {
        guard data.count <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreNBT.decompressText1) }
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 16, zlibVersion(), Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw RuriError.message(Messages.CoreNBT.streamText2) }
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
                guard written <= limit - output.count else { throw RuriError.message(Messages.CoreNBT.writtenText1) }
                output.append(contentsOf: buffer.prefix(written))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0 else { throw RuriError.message(Messages.CoreNBT.writtenText2) }
                    return output
                }
                guard status == Z_OK, written > 0 || stream.avail_in > 0 else { throw RuriError.message(Messages.CoreNBT.writtenText3) }
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
        guard decoded.count <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreNBT.compressText1) }
        bytes = Array(decoded)
    }
    public mutating func read() throws -> NBTValue {
        guard try byte() == 10 else { throw RuriError.message(Messages.CoreNBT.readText1) }
        _ = try text()
        let value = try payload(10, depth: 0)
        guard offset == bytes.count else { throw RuriError.message(Messages.CoreNBT.valueText1) }
        return value
    }
    // Copy untouched tags verbatim: NBTValue deliberately does not retain numeric
    // widths, array types or empty-list subtypes, so it cannot be used as a writer.
    static func updatingDataPacks(_ data: Data, enabled: [String], disabled: [String]) throws -> Data {
        var reader = try NBTReader(data: data)
        guard try reader.byte() == 10 else { throw RuriError.message(Messages.CoreNBT.readText1) }
        _ = try reader.text()
        var result = Data(reader.bytes[..<reader.offset])
        let replacements = try ["Enabled": stringList("Enabled", enabled), "Disabled": stringList("Disabled", disabled)]
        result += try reader.rewriteCompound(path: ["Data", "DataPacks"], replacements: replacements, depth: 0)
        guard reader.offset == reader.bytes.count, result.count <= 32 * 1024 * 1024 else { throw RuriError.message(Messages.CoreNBT.replacementsText1) }
        return data.starts(with: [0x1f, 0x8b]) ? try Gzip.compress(result) : result
    }
    private mutating func rewriteCompound(path: [String], replacements: [String: Data], depth: Int) throws -> Data {
        remainingTags -= 1
        guard remainingTags >= 0, depth <= 64 else { throw RuriError.message(Messages.CoreNBT.rewriteCompoundText1) }
        var result = Data(), seen = Set<String>()
        while true {
            let start = offset, type = try byte()
            if type == 0 { break }
            let name = try text()
            guard seen.insert(name).inserted else { throw RuriError.message(Messages.CoreNBT.nameText1) }
            if name == path.first {
                guard type == 10 else { throw RuriError.message(Messages.CoreNBT.nameText2) }
                result += Data(bytes[start..<offset])
                result += try rewriteCompound(path: Array(path.dropFirst()), replacements: replacements, depth: depth + 1)
            } else {
                _ = try payload(type, depth: depth + 1)
                result += path.isEmpty ? replacements[name] ?? Data(bytes[start..<offset]) : Data(bytes[start..<offset])
            }
        }
        if path.isEmpty {
            for name in replacements.keys.sorted() where !seen.contains(name) { result += replacements[name]! }
        } else if let name = path.first, !seen.contains(name) {
            guard path == ["DataPacks"] else { throw RuriError.message(Messages.CoreNBT.nameText3) }
            result += Data([10]) + (try Self.encodedString(name))
            for name in replacements.keys.sorted() { result += replacements[name]! }
            result.append(0)
        }
        result.append(0)
        return result
    }
    private static func stringList(_ name: String, _ values: [String]) throws -> Data {
        guard values.count <= 4096 else { throw RuriError.message(Messages.CoreNBT.stringListText1) }
        let count = UInt32(values.count)
        var result = Data([9]) + (try encodedString(name)) + Data([8, UInt8(truncatingIfNeeded: count >> 24), UInt8(truncatingIfNeeded: count >> 16), UInt8(truncatingIfNeeded: count >> 8), UInt8(truncatingIfNeeded: count)])
        for value in values { result += try encodedString(value) }
        return result
    }
    private static func encodedString(_ value: String) throws -> Data {
        var bytes = Data()
        for unit in value.utf16 {
            if (1...0x7f).contains(unit) { bytes.append(UInt8(unit)) }
            else if unit <= 0x7ff { bytes.append(contentsOf: [0xc0 | UInt8(unit >> 6), 0x80 | UInt8(unit & 0x3f)]) }
            else { bytes.append(contentsOf: [0xe0 | UInt8(unit >> 12), 0x80 | UInt8((unit >> 6) & 0x3f), 0x80 | UInt8(unit & 0x3f)]) }
        }
        guard bytes.count <= 65535 else { throw RuriError.message(Messages.CoreNBT.bytesText1) }
        return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 255)]) + bytes
    }
    private mutating func payload(_ tag: UInt8, depth: Int) throws -> NBTValue {
        remainingTags -= 1
        guard remainingTags >= 0, depth <= 64 else { throw RuriError.message(Messages.CoreNBT.rewriteCompoundText1) }
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
            guard count <= (bytes.count - offset) / width else { throw RuriError.message(Messages.CoreNBT.widthText1) }
            let length = count * width; defer { offset += length }
            return .array(Data(bytes[offset..<(offset + length)]))
        case 8: return .string(try text())
        case 9:
            let subtype = try byte(); let count = try count()
            guard count <= remainingTags, count == 0 || (1...12).contains(subtype) else { throw RuriError.message(Messages.CoreNBT.countText1) }
            var values: [NBTValue] = []; values.reserveCapacity(count)
            for _ in 0..<count { values.append(try payload(subtype, depth: depth + 1)) }
            return .list(values)
        case 10:
            var value: [String: NBTValue] = [:]
            while true {
                let type = try byte()
                if type == 0 { break }
                let key = try text()
                guard value[key] == nil else { throw RuriError.message(Messages.CoreNBT.nameText1) }
                value[key] = try payload(type, depth: depth + 1)
            }
            return .compound(value)
        default: throw RuriError.message(Messages.CoreNBT.keyText1(String(describing: tag)))
        }
    }
    private mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw RuriError.message(Messages.CoreNBT.byteText1) }
        defer { offset += 1 }; return bytes[offset]
    }
    private mutating func unsigned(_ count: Int) throws -> UInt64 {
        guard count <= bytes.count - offset else { throw RuriError.message(Messages.CoreNBT.unsignedText1) }
        var value: UInt64 = 0
        for _ in 0..<count { value = (value << 8) | UInt64(try byte()) }
        return value
    }
    private mutating func count() throws -> Int {
        let value = Int32(bitPattern: UInt32(try unsigned(4)))
        guard value >= 0 else { throw RuriError.message(Messages.CoreNBT.valueText2) }; return Int(value)
    }
    private mutating func text() throws -> String {
        let length = Int(try unsigned(2))
        guard length <= bytes.count - offset else { throw RuriError.message(Messages.CoreNBT.lengthText1) }
        let data = Data(bytes[offset..<(offset + length)]); offset += length
        if let result = String(data: data, encoding: .utf8) { return result }
        // Java NBT strings use modified UTF-8, including CESU-8 surrogate pairs.
        let input = Array(data); var units: [UInt16] = []; var i = 0
        while i < input.count {
            let a = input[i]; i += 1
            if a < 0x80 { units.append(UInt16(a)) }
            else if a & 0xe0 == 0xc0 {
                guard i < input.count, input[i] & 0xc0 == 0x80 else { throw RuriError.message(Messages.CoreNBT.aText1) }
                units.append(UInt16(a & 0x1f) << 6 | UInt16(input[i] & 0x3f)); i += 1
            } else if a & 0xf0 == 0xe0 {
                guard i + 1 < input.count, input[i] & 0xc0 == 0x80, input[i + 1] & 0xc0 == 0x80 else { throw RuriError.message(Messages.CoreNBT.aText1) }
                units.append(UInt16(a & 0x0f) << 12 | UInt16(input[i] & 0x3f) << 6 | UInt16(input[i + 1] & 0x3f)); i += 2
            } else { throw RuriError.message(Messages.CoreNBT.aText1) }
        }
        return String(decoding: units, as: UTF16.self)
    }
}
