import RuriLocalization
import Foundation

public struct ModpackOrigin: Codable, Equatable, Sendable {
    public enum Provider: String, Codable, Sendable { case modrinth, curseforge, mcbbs }
    public let provider: Provider
    public let projectID: String?
    public let versionID: String?
    public let fileAPI: URL?
    public init(provider: Provider, projectID: String? = nil, versionID: String? = nil, fileAPI: URL? = nil) {
        self.provider = provider; self.projectID = projectID; self.versionID = versionID; self.fileAPI = fileAPI
    }
}

struct ModpackDescriptor: Sendable {
    let version: String
    var origin: ModpackOrigin?
    var identities: [String: String] = [:]
    var forcedProjects: Set<String> = []
}

public struct InstalledModpack: Codable, Sendable {
    public struct File: Codable, Sendable {
        public let path: String
        public let sha1: String
        public let size: Int64
        public let force: Bool
        public let identities: [String]
    }
    public var schemaVersion = 1
    public let format: String
    public let name: String
    public let version: String
    public let origin: ModpackOrigin?
    public var settings: GameInstance
    public let files: [File]
}

public enum ModpackRegistry {
    public static func load(paths: LauncherPaths, instanceID: UUID) throws -> InstalledModpack? {
        let file = paths.instance(instanceID).appendingPathComponent("modpack-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try read(file, game: paths.game(instanceID))
    }
    static func read(_ file: URL, game: URL) throws -> InstalledModpack {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) <= 64 * 1024 * 1024 else { throw RuriError.message(Messages.CoreModpackRegistry.infoText1) }
        let record = try JSONDecoder().decode(InstalledModpack.self, from: Data(contentsOf: file))
        try validate(record, game: game); return record
    }
    static func validate(_ record: InstalledModpack, game: URL) throws {
        guard record.schemaVersion == 1, ["Modrinth", "CurseForge", "MCBBS", "HMCL"].contains(record.format), record.files.count <= 150_000,
              Set(record.files.map { $0.path.lowercased() }).count == record.files.count else { throw RuriError.message(Messages.CoreModpackRegistry.validateText1) }
        try InstanceTransfer.validate(record.settings)
        for file in record.files {
            _ = try LauncherPaths.safePath(file.path, within: game)
            guard file.sha1.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil, file.size >= 0 else { throw RuriError.message(Messages.CoreModpackRegistry.validateText2) }
        }
        if let origin = record.origin {
            for id in [origin.projectID, origin.versionID].compactMap({ $0 }) {
                guard id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreModpackRegistry.originText1) }
            }
            if let url = origin.fileAPI {
                guard ["http", "https"].contains(url.scheme), url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw RuriError.message(Messages.CoreModpackRegistry.urlText1) }
            }
        }
    }
    static func save(_ record: InstalledModpack, paths: LauncherPaths, instanceID: UUID) throws {
        try validate(record, game: paths.game(instanceID))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: paths.instance(instanceID).appendingPathComponent("modpack-state.json"), options: .atomic)
    }
    static func capture(_ prepared: PreparedInstanceImport, instance: GameInstance, paths: LauncherPaths, content: [ContentInstallation]) throws -> InstalledModpack? {
        if var inherited = prepared.inheritedModpack {
            inherited.settings.id = instance.id
            return inherited // preserve the original baseline, including user edits made before export
        }
        guard let descriptor = prepared.modpack else { return nil }
        let entries = try FileTree.entries(in: paths.game(instance.id))
        var files: [InstalledModpack.File] = []
        let force = Dictionary(prepared.selectedPackFiles.map { ($0.path, $0.force) }, uniquingKeysWith: { first, _ in first })
        for entry in entries where !entry.directory {
            try Task.checkCancellation()
            var identities: [String] = []
            var forced = force[entry.path] ?? false
            if let identity = descriptor.identities[entry.path] { identities.append(identity) }
            if let record = content.first(where: { $0.record.relativePath == entry.path })?.record {
                identities.append("\(record.provider):\(record.projectID)")
                forced = forced || descriptor.forcedProjects.contains(record.projectID)
            }
            if entry.path.hasPrefix("mods/"), let id = ContentManager.modInfo(entry.url)?.id { identities.append("mod:\(id)") }
            files.append(.init(path: entry.path, sha1: try InstanceTransfer.sha1(entry.url), size: entry.size, force: forced, identities: Array(Set(identities)).sorted()))
        }
        var settings = prepared.instance; settings.id = instance.id; settings.javaPath = nil
        return InstalledModpack(format: prepared.format, name: prepared.instance.name, version: descriptor.version, origin: descriptor.origin, settings: settings, files: files)
    }
}
