import Foundation

public struct VersionCatalog: Codable, Sendable {
    public struct Latest: Codable, Sendable { public let release: String; public let snapshot: String }
    public let latest: Latest
    public let versions: [VersionEntry]
}
public struct VersionEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let type: String
    public let url: URL
    public let sha1: String?
    public let releaseTime: String
    public var isRelease: Bool { type == "release" }
}
public struct Artifact: Codable, Sendable {
    public let path: String?
    public let url: URL?
    public let sha1: String?
    public let size: Int64?
    public init(path: String? = nil, url: URL?, sha1: String? = nil, size: Int64? = nil) {
        self.path = path; self.url = url; self.sha1 = sha1; self.size = size
    }
    private enum CodingKeys: String, CodingKey { case path, url, sha1, size }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        let address = try c.decodeIfPresent(String.self, forKey: .url)
        if let address, !address.isEmpty {
            guard let parsed = URL(string: address) else { throw DecodingError.dataCorruptedError(forKey: .url, in: c, debugDescription: "Invalid artifact URL") }
            url = parsed
        } else { url = nil }
        let hash = try c.decodeIfPresent(String.self, forKey: .sha1)
        sha1 = hash?.isEmpty == true ? nil : hash
        size = try c.decodeIfPresent(Int64.self, forKey: .size)
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(path, forKey: .path); try c.encodeIfPresent(url?.absoluteString, forKey: .url)
        try c.encodeIfPresent(sha1, forKey: .sha1); try c.encodeIfPresent(size, forKey: .size)
    }
}
public struct Rule: Codable, Sendable {
    public struct OS: Codable, Sendable { public let name: String?; public let arch: String?; public let version: String? }
    public let action: String
    public let os: OS?
    public let features: [String: Bool]?
    public func matches(architecture: String, features enabledFeatures: [String: Bool] = [:]) -> Bool {
        if let os {
            if let name = os.name, name != "osx" { return false }
            if let arch = os.arch {
                let normalized = ["arm64": "aarch64", "amd64": "x86_64"]
                if (normalized[arch] ?? arch) != (normalized[architecture] ?? architecture) { return false }
            }
            if let pattern = os.version {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                if "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)".range(of: pattern, options: .regularExpression) == nil { return false }
            }
        }
        for (key, value) in features ?? [:] where (enabledFeatures[key] ?? false) != value { return false }
        return true
    }
    public static func allows(_ rules: [Rule]?, architecture: String, features: [String: Bool] = [:]) -> Bool {
        guard let rules else { return true }
        var allowed = false
        for rule in rules where rule.matches(architecture: architecture, features: features) { allowed = rule.action == "allow" }
        return allowed
    }
}
public enum LaunchArgument: Codable, Sendable {
    case text(String)
    case conditional([Rule], [String])
    private enum CodingKeys: CodingKey { case rules, value }
    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) { self = .text(text); return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let values = try (try? c.decode([String].self, forKey: .value)) ?? [c.decode(String.self, forKey: .value)]
        self = .conditional(try c.decode([Rule].self, forKey: .rules), values)
    }
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .text(let value): var c = encoder.singleValueContainer(); try c.encode(value)
        case .conditional(let rules, let values):
            var c = encoder.container(keyedBy: CodingKeys.self); try c.encode(rules, forKey: .rules); try c.encode(values, forKey: .value)
        }
    }
    public func values(architecture: String, features: [String: Bool]) -> [String] {
        switch self { case .text(let text): [text]; case .conditional(let rules, let values): Rule.allows(rules, architecture: architecture, features: features) ? values : [] }
    }
}
public struct Library: Codable, Sendable {
    public struct Downloads: Codable, Sendable { public var artifact: Artifact?; public var classifiers: [String: Artifact]? }
    public struct Extraction: Codable, Sendable { public let exclude: [String]? }
    public let name: String
    public var downloads: Downloads?
    public var url: URL?
    public let rules: [Rule]?
    public let natives: [String: String]?
    public let extract: Extraction?
    public var identity: String { let p = name.split(separator: ":"); return p.prefix(2).joined(separator: ":") + (p.count > 3 ? ":\(p[3])" : "") }
    public func artifact() throws -> Artifact? {
        if let artifact = downloads?.artifact { return artifact }
        if downloads != nil { return nil }
        let path = try Self.mavenPath(name)
        return Artifact(path: path, url: (url ?? URL(string: "https://libraries.minecraft.net/")!).appendingPathComponent(path))
    }
    public static func mavenPath(_ coordinate: String) throws -> String {
        let extParts = coordinate.split(separator: "@", omittingEmptySubsequences: false)
        let parts = extParts[0].split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (3...4).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && $0 != ".." }) else { throw RuriError.message("无效 Maven 坐标：\(coordinate)") }
        let ext = extParts.count > 1 ? String(extParts[1]) : "jar"
        guard ext.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { throw RuriError.message("无效 Maven 扩展名") }
        return "\(parts[0].replacingOccurrences(of: ".", with: "/"))/\(parts[1])/\(parts[2])/\(parts[1])-\(parts[2])\(parts.count == 4 ? "-" + parts[3] : "").\(ext)"
    }
    public func nativeArtifact(architecture: String) -> Artifact? {
        guard let classifier = natives?["osx"] else { return nil }
        return downloads?.classifiers?[classifier.replacingOccurrences(of: "${arch}", with: "64")]
    }
}
public struct VersionManifest: Codable, Sendable {
    public struct Arguments: Codable, Sendable { public var game: [LaunchArgument]?; public var jvm: [LaunchArgument]? }
    public struct JavaVersion: Codable, Sendable { public let majorVersion: Int; public let component: String? }
    public struct AssetIndex: Codable, Sendable { public let id: String; public let url: URL; public let sha1: String?; public let size: Int64? }
    public struct Logging: Codable, Sendable {
        public struct Client: Codable, Sendable { public let argument: String; public let file: LogFile }
        public struct LogFile: Codable, Sendable { public let id: String; public let url: URL; public let sha1: String?; public let size: Int64? }
        public let client: Client?
    }
    public var id: String
    public var type: String?
    public var mainClass: String?
    public var inheritsFrom: String?
    public var jar: String?
    public var arguments: Arguments?
    public var minecraftArguments: String?
    public var libraries: [Library]
    public var downloads: [String: Artifact]?
    public var assetIndex: AssetIndex?
    public var assets: String?
    public var javaVersion: JavaVersion?
    public var logging: Logging?
    public var requiredJava: Int { javaVersion?.majorVersion ?? 8 }
    public func merging(child: VersionManifest) -> VersionManifest {
        var result = self
        result.id = child.id; result.inheritsFrom = nil; result.jar = child.jar ?? jar ?? id
        result.mainClass = child.mainClass ?? mainClass
        result.type = child.type ?? type
        result.arguments = Arguments(game: (arguments?.game ?? []) + (child.arguments?.game ?? []), jvm: (arguments?.jvm ?? []) + (child.arguments?.jvm ?? []))
        result.minecraftArguments = child.minecraftArguments ?? minecraftArguments
        let keys = Set(child.libraries.map(\.identity))
        var seen = Set<String>()
        let uniqueChild = child.libraries.reversed().filter { seen.insert($0.identity).inserted }.reversed()
        result.libraries = libraries.filter { !keys.contains($0.identity) } + uniqueChild
        result.javaVersion = child.javaVersion ?? javaVersion
        result.downloads = child.downloads ?? downloads
        result.assetIndex = child.assetIndex ?? assetIndex
        result.logging = child.logging ?? logging
        return result
    }
}
public struct AssetObjects: Codable, Sendable {
    public struct Object: Codable, Sendable { public let hash: String; public let size: Int64 }
    public let objects: [String: Object]
    public let virtual: Bool?
    public let map_to_resources: Bool?
}
