import RuriLocalization
import Foundation

enum OptiFineCatalog {
    static let root = URL(string: "https://bmclapi2.bangbang93.com/optifine")!
    struct Release: Decodable, Sendable {
        let mcversion: String
        let type: String
        let patch: String
        let forge: String?
        var version: String { type + "_" + patch }
        var preview: Bool { patch.hasPrefix("pre") || patch.hasPrefix("alpha") }
        func url() throws -> URL { try EndpointURL.build(base: root, path: [mcversion, type, patch]) }
    }
    static func normalized(_ version: String, game: String) -> String {
        for prefix in [game, ["1.8": "1.8.0", "1.9": "1.9.0"][game]].compactMap({ $0 }) where version.hasPrefix(prefix + "_") {
            return String(version.dropFirst(prefix.count + 1))
        }
        return version
    }
    static func releases(game: String, client: HTTPClient = .shared) async throws -> [Release] {
        if game.range(of: "^1\\.[0-5](?:\\.|$)", options: .regularExpression) != nil { return [] }
        let lookup = ["1.8": "1.8.0", "1.9": "1.9.0"][game] ?? game
        let url = try EndpointURL.build(base: root, path: [lookup])
        let entries = try await client.get([Release].self, from: url)
        var seen = Set<String>()
        return entries.filter {
            ($0.mcversion == game || $0.mcversion == lookup) && $0.type.range(of: "^HD_[A-Z](?:_[A-Z][0-9]+)?$", options: .regularExpression) != nil
                && $0.patch.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil && seen.insert($0.version).inserted
        }.sorted {
            if $0.preview != $1.preview { return !$0.preview }
            return $0.version.compare($1.version, options: .numeric) == .orderedDescending
        }
    }
}

/// Read ConstantValue fields without executing the installer's Config class.
enum OptiFineClassMetadata {
    static func values(_ data: Data) throws -> [String: String] {
        var offset = 0
        func number(_ count: Int) throws -> Int {
            guard offset + count <= data.count else { throw invalid() }
            var value = 0
            for byte in data[offset..<(offset + count)] { value = (value << 8) | Int(byte) }
            offset += count; return value
        }
        func skip(_ count: Int) throws { guard count >= 0, count <= data.count - offset else { throw invalid() }; offset += count }
        guard try number(4) == 0xcafebabe else { throw invalid() }
        try skip(4)
        let count = try number(2)
        var text: [Int: String] = [:], strings: [Int: Int] = [:], index = 1
        while index < count {
            switch try number(1) {
            case 1:
                let length = try number(2), start = offset; try skip(length)
                text[index] = String(decoding: data[start..<offset], as: UTF8.self)
            case 8: strings[index] = try number(2)
            case 3, 4, 9, 10, 11, 12, 17, 18: try skip(4)
            case 5, 6: try skip(8); index += 1
            case 7, 16, 19, 20: try skip(2)
            case 15: try skip(3)
            default: throw invalid()
            }
            index += 1
        }
        try skip(6)
        let interfaces = try number(2); try skip(interfaces * 2)
        let fields = try number(2)
        var result: [String: String] = [:]
        for _ in 0..<fields {
            try skip(2); let name = text[try number(2)]; try skip(2)
            let attributes = try number(2)
            for _ in 0..<attributes {
                let attribute = text[try number(2)], length = try number(4)
                if attribute == "ConstantValue", length == 2 {
                    let value = try number(2)
                    if let name, let string = strings[value], let value = text[string] { result[name] = value }
                } else { try skip(length) }
            }
        }
        return result
    }
    private static func invalid() -> RuriError { .message(Messages.CoreOptiFineCatalog.invalidVersionInfo.localized) }
}
