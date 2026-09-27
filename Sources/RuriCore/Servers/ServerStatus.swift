import Foundation
import ImageIO
import RuriLocalization

public enum ServerStatusError: String, Error, LocalizedError, Sendable {
    case timeout, dns, connection, response
    public var errorDescription: String? {
        switch self {
        case .timeout: Messages.Servers.timeout.localized
        case .dns: Messages.Servers.dnsFailed.localized
        case .connection: Messages.Servers.connectionFailed.localized
        case .response: Messages.Servers.invalidResponse.localized
        }
    }
}

public struct ServerStatus: Sendable {
    public let description: String
    public let version: String?
    public let protocolVersion: Int?
    public let online: Int?
    public let maximum: Int?
    public let playerSample: [String]
    public let icon: Data?
    public var latencyMilliseconds: Int?
    public let queriedAt: Date

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 1_048_576, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ServerStatusError.response }
        var budget = 16384
        func text(_ value: Any?, depth: Int = 0) -> String {
            guard budget > 0, depth < 16 else { return "" }
            if let value = value as? String {
                let value = String(value.prefix(budget)); budget -= value.count
                return value.replacingOccurrences(of: "§[0-9A-FK-ORa-fk-or]", with: "", options: .regularExpression)
            }
            if let values = value as? [Any] { return values.prefix(256).map { text($0, depth: depth + 1) }.joined() }
            if let value = value as? [String: Any] { return text(value["text"] ?? value["translate"], depth: depth + 1) + text(value["extra"], depth: depth + 1) }
            return ""
        }
        let description = text(json["description"])
        let version = json["version"] as? [String: Any], players = json["players"] as? [String: Any]
        func number(_ value: Any?) -> Int? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  value.doubleValue >= 0, value.doubleValue <= Double(Int32.max), value.doubleValue.rounded() == value.doubleValue else { return nil }
            return value.intValue
        }
        var icon: Data?
        if let encoded = json["favicon"] as? String, encoded.hasPrefix("data:image/png;base64,"), encoded.utf8.count <= 1_048_576,
           let bytes = Data(base64Encoded: String(encoded.dropFirst(22))) { icon = validatedIcon(bytes) }
        let sample = (players?["sample"] as? [[String: Any]] ?? []).prefix(100).compactMap { ($0["name"] as? String).map { String($0.prefix(256)) } }
        return .init(description: description, version: (version?["name"] as? String).map { String($0.prefix(1024)) }, protocolVersion: number(version?["protocol"]),
                     online: number(players?["online"]), maximum: number(players?["max"]), playerSample: sample, icon: icon, queriedAt: Date())
    }
    public static func validatedIcon(_ data: Data) -> Data? {
        guard data.count <= 786432, data.starts(with: [137,80,78,71,13,10,26,10]),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 256, height <= 256 else { return nil }
        return data
    }
}

enum ServerPacket {
    static func varInt(_ value: Int32) -> Data {
        var value = UInt32(bitPattern: value), result = Data()
        repeat { var byte = UInt8(value & 127); value >>= 7; if value != 0 { byte |= 128 }; result.append(byte) } while value != 0
        return result
    }
    static func integer(_ data: Data, offset: inout Int) throws -> Int? {
        let initial = offset
        var value: UInt32 = 0
        for index in 0..<5 {
            guard offset < data.count else { offset = initial; return nil }
            let byte = data[offset]; offset += 1
            guard index != 4 || byte & 0xf0 == 0 else { throw ServerStatusError.response }
            value |= UInt32(byte & 127) << (7 * index)
            if byte & 128 == 0 { guard value <= Int32.max else { throw ServerStatusError.response }; return Int(value) }
        }
        throw ServerStatusError.response
    }
    static func string(_ value: String) -> Data { let bytes = Data(value.utf8); return varInt(Int32(bytes.count)) + bytes }
    static func frame(_ payload: Data) -> Data { varInt(Int32(payload.count)) + payload }
    static func handshake(_ address: ServerAddress, protocolVersion: Int32) -> Data {
        frame(Data([0]) + varInt(protocolVersion) + string(address.host) + Data([UInt8(address.port >> 8), UInt8(address.port & 255), 1])) + Data([1, 0])
    }
    static func take(_ buffer: inout Data) throws -> Data? {
        var offset = 0
        guard let length = try integer(buffer, offset: &offset) else { return nil }
        guard length > 0, length <= 1_048_576 else { throw ServerStatusError.response }
        guard buffer.count >= offset + length else { return nil }
        let result = Data(buffer[offset..<(offset + length)])
        buffer = Data(buffer.dropFirst(offset + length))
        return result
    }
}
