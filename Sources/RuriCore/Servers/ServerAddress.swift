import Foundation
import Darwin
import RuriLocalization

public struct ServerAddress: Hashable, Codable, Sendable {
    public let host: String
    public let port: UInt16
    public let explicitPort: Bool
    public var isIP: Bool { Self.ip(host) != nil }
    public var authority: String { (host.contains(":") ? "[\(host)]" : host) + (explicitPort || port != 25565 ? ":\(port)" : "") }
    public var key: String { (host.contains(":") ? "[\(host)]" : host) + ":\(port)" }

    public init(_ input: String) throws {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func invalid() -> RuriError { .message(Messages.Servers.invalidAddress) }
        guard !value.isEmpty, value.utf8.count <= 1024,
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              !value.contains(where: { "/\\@?#%".contains($0) }) else { throw invalid() }
        let rawHost: String, rawPort: String?
        if value.hasPrefix("[") {
            guard let end = value.firstIndex(of: "]") else { throw invalid() }
            rawHost = String(value[value.index(after: value.startIndex)..<end])
            let suffix = String(value[value.index(after: end)...])
            guard suffix.isEmpty || suffix.hasPrefix(":") else { throw invalid() }
            rawPort = suffix.isEmpty ? nil : String(suffix.dropFirst())
            guard rawHost.contains(":"), Self.ip(rawHost) != nil else { throw invalid() }
        } else if value.filter({ $0 == ":" }).count > 1 {
            guard Self.ip(value) != nil else { throw invalid() }
            rawHost = value; rawPort = nil
        } else {
            let parts = value.split(separator: ":", omittingEmptySubsequences: false)
            rawHost = String(parts[0]); rawPort = parts.count == 2 ? String(parts[1]) : nil
        }
        if let rawPort {
            guard !rawPort.isEmpty, rawPort.utf8.allSatisfy({ (48...57).contains($0) }), let number = UInt16(rawPort), number > 0 else { throw invalid() }
            port = number
        } else { port = 25565 }
        explicitPort = rawPort != nil
        if let ip = Self.ip(rawHost) { host = ip }
        else {
            guard !rawHost.contains(":"), !rawHost.contains("["), !rawHost.contains("]"),
                  let ascii = URL(string: "http://" + rawHost)?.host?.lowercased() else { throw invalid() }
            let normalized = ascii.hasSuffix(".") ? String(ascii.dropLast()) : ascii
            let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
            guard normalized.utf8.count <= 253, !labels.isEmpty, labels.allSatisfy({ label in
                !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
            }) else { throw invalid() }
            host = normalized
        }
    }
    private static func ip(_ value: String) -> String? {
        for family in [AF_INET, AF_INET6] {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard inet_pton(family, value, &bytes) == 1 else { continue }
            var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            guard inet_ntop(family, &bytes, &output, socklen_t(output.count)) != nil else { return nil }
            return String(decoding: output.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        return nil
    }
    public init(from decoder: any Decoder) throws { try self.init(decoder.singleValueContainer().decode(String.self)) }
    public func encode(to encoder: any Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(authority) }
}
