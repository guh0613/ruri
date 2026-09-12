import RuriLocalization
import Foundation

public struct LauncherPaths: Codable, Sendable {
    public let root: URL
    public let directories: [GameDirectory]
    public let instanceDirectories: [UUID: UUID]
    public let newInstanceDirectoryID: UUID
    public let instanceRunDirectories: [UUID: GameRunDirectory]?
    public let instanceCustomDirectories: [UUID: CustomRunDirectory]?
    public let instanceRepositoryVersions: [UUID: String]?
    /// Used only while installing an unpublished repository import.
    var repositoryImportID: UUID?
    public init(root: URL? = nil, directories: [GameDirectory] = [], instanceDirectories: [UUID: UUID] = [:], newInstanceDirectoryID: UUID = GameDirectory.defaultID, instanceRunDirectories: [UUID: GameRunDirectory]? = nil, instanceCustomDirectories: [UUID: CustomRunDirectory]? = nil, instanceRepositoryVersions: [UUID: String]? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ruri", isDirectory: true)
        self.directories = directories; self.instanceDirectories = instanceDirectories; self.newInstanceDirectoryID = newInstanceDirectoryID
        self.instanceRunDirectories = instanceRunDirectories
        self.instanceCustomDirectories = instanceCustomDirectories
        self.instanceRepositoryVersions = instanceRepositoryVersions
    }
    public var libraries: URL { root.appendingPathComponent("libraries") }
    public var assets: URL { root.appendingPathComponent("assets") }
    public var versions: URL { root.appendingPathComponent("versions") }
    public var instances: URL { root.appendingPathComponent("instances") }
    public var runtimes: URL { root.appendingPathComponent("runtimes") }
    public var cache: URL { root.appendingPathComponent("cache") }
    public var state: URL { root.appendingPathComponent("state.json") }
    public func instance(_ id: UUID) -> URL {
        if repositoryImportID == id { return repositoryImportWorkspace(id).appendingPathComponent("metadata") }
        return directoryRoot(directoryID(for: id)).appendingPathComponent(isMinecraftDirectory(directoryID(for: id)) ? ".ruri/instances" : "instances").appendingPathComponent(id.uuidString)
    }
    public func versionDirectory(_ id: UUID) -> URL {
        if repositoryImportID == id { return repositoryImportWorkspace(id).appendingPathComponent("version") }
        return directoryRoot(directoryID(for: id)).appendingPathComponent("versions").appendingPathComponent(instanceRepositoryVersions?[id] ?? "unavailable-\(id.uuidString)")
    }
    func repositoryImportWorkspace(_ id: UUID) -> URL { directoryRoot(directoryID(for: id)).appendingPathComponent(".ruri/imports/\(id.uuidString)") }
    func stagingRepositoryImport(_ instance: GameInstance) -> LauncherPaths {
        var result = including(instance); result.repositoryImportID = instance.id; return result
    }
    func clientJar(_ jarID: String, instance: GameInstance) throws -> URL {
        if repositoryImportID == instance.id, jarID == instance.repositoryVersionID {
            return try Self.safePath(jarID + ".jar", within: versionDirectory(instance.id))
        }
        return try Self.safePath("\(jarID)/\(jarID).jar", within: resources(for: instance).versions)
    }
    public func game(_ id: UUID) -> URL {
        if runDirectory(for: id) == .custom { return instanceCustomDirectories?[id]?.url ?? root.appendingPathComponent("unavailable-run-directories/\(id.uuidString)") }
        if isMinecraftDirectory(directoryID(for: id)) { return runDirectory(for: id) == .isolated ? versionDirectory(id) : directoryRoot(directoryID(for: id)) }
        return (runDirectory(for: id) == .isolated ? instance(id) : directoryRoot(directoryID(for: id))).appendingPathComponent("minecraft")
    }
    public func manifest(_ id: UUID) -> URL {
        if let version = instanceRepositoryVersions?[id] { return versionDirectory(id).appendingPathComponent(version + ".json") }
        return instance(id).appendingPathComponent("version.json")
    }
    public func prepare() throws {
        for url in [root, libraries, assets, versions, instances, runtimes, cache] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }
    public static func safePath(_ path: String, within root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { throw RuriError.message(Messages.CoreLauncherPaths.safePathText1(String(describing: path))) }
        let baseURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let base = baseURL.path + "/"
        var resolved = baseURL
        // Foundation does not resolve an intermediate symlink reliably when the
        // final file does not exist yet. Validate each existing prefix instead.
        for component in path.split(separator: "/") where component != "." {
            resolved = resolved.appendingPathComponent(String(component)).standardizedFileURL
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: resolved.path)) != nil {
                resolved = resolved.resolvingSymlinksInPath()
            }
            guard resolved.path.hasPrefix(base) else { throw RuriError.message(Messages.CoreLauncherPaths.resolvedText1(String(describing: path))) }
        }
        return resolved
    }
}
