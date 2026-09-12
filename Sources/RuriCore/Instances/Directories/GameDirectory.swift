import RuriLocalization
import Foundation

/// A registered game folder. Standard Minecraft repositories own their
/// resources; older Ruri collections retain the shared launcher cache.
public struct GameDirectory: Codable, Identifiable, Equatable, Sendable {
    public static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public let id: UUID
    public var name: String
    public var url: URL
    public var bookmark: Data?
    public let createdAt: Date
    public enum Layout: String, Codable, Sendable { case managed, minecraft }
    public var layout: Layout?
    public var isMinecraft: Bool { layout == .minecraft }
    static let markerName = ".ruri-directory.json"
    struct Marker: Codable { let schema: Int; let id: UUID; var layout: Layout? }

    /// Compatibility entry point for older Ruri-managed collections.
    /// New and existing Minecraft repositories use MinecraftFolderStore.
    public static func create(name: String, at url: URL, paths: LauncherPaths) throws -> GameDirectory {
        let directory = GameDirectory(id: UUID(), name: try validName(name), url: url.standardizedFileURL.resolvingSymlinksInPath(), bookmark: nil, createdAt: Date())
        try paths.checkNewDirectory(directory)
        let entries = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        if entries.contains(where: { $0.lastPathComponent == markerName }) {
            let markerURL = directory.url.appendingPathComponent(markerName)
            let values = try markerURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1024,
                  entries.allSatisfy({ [markerName, ".DS_Store", "instances", "minecraft"].contains($0.lastPathComponent) }) else { throw RuriError.message(Messages.CoreGameDirectory.directoryHasData) }
            let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: markerURL))
            guard !paths.directories.contains(where: { $0.id == marker.id }), marker.id != defaultID else { throw RuriError.message(Messages.CoreGameDirectory.directoryAlreadyRegistered) }
            let instances = directory.url.appendingPathComponent("instances")
            if FileManager.default.fileExists(atPath: instances.path) {
                guard try instances.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                      try FileManager.default.contentsOfDirectory(atPath: instances.path).allSatisfy({ $0 == ".DS_Store" }) else { throw RuriError.message(Messages.CoreGameDirectory.directoryHasInstances) }
            }
            var existing = GameDirectory(id: marker.id, name: directory.name, url: directory.url, bookmark: nil, createdAt: Date())
            try existing.validateAvailability()
            existing.bookmark = try existing.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            return existing
        }
        guard entries.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else {
            throw RuriError.message(Messages.CoreGameDirectory.directoryMustBeEmpty)
        }
        var result = directory
        result.bookmark = try directory.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try JSONEncoder().encode(Marker(schema: 1, id: directory.id)).write(to: directory.url.appendingPathComponent(markerName), options: .withoutOverwriting)
        return result
    }

    public func validateAvailability() throws {
        do {
            guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message(Messages.CoreGameDirectory.pathNotDirectory) }
            let marker = url.appendingPathComponent(Self.markerName)
            let values = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1024 else { throw RuriError.message(Messages.CoreGameDirectory.invalidMarker) }
            let record = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: marker))
            guard record.schema == 1, record.id == id, (record.layout ?? .managed) == (layout ?? .managed) else { throw RuriError.message(Messages.CoreGameDirectory.identityMismatch) }
        } catch {
            throw RuriError.message(Messages.CoreGameDirectory.inaccessibleDirectory(name, url.path, error.localizedDescription))
        }
    }

    /// Resolve Finder moves without UI or mounting an absent volume. Identity
    /// validation prevents a new folder at an old mount point from replacing it.
    public func resolvingBookmark() -> GameDirectory {
        guard let bookmark else { return self }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return self }
        var result = self; result.url = resolved.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? result.validateAvailability()) != nil else { return self }
        if stale { result.bookmark = try? result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        return result
    }

    public func relocated(to url: URL, paths: LauncherPaths) throws -> GameDirectory {
        var result = self; result.url = url.standardizedFileURL.resolvingSymlinksInPath()
        try result.validateAvailability()
        try paths.checkNewDirectory(result)
        result.bookmark = try result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return result
    }

    public static func validName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw RuriError.message(Messages.CoreGameDirectory.invalidName) }
        return name
    }
}

extension LauncherPaths {
    public func configured(with state: PersistentState) -> LauncherPaths {
        LauncherPaths(root: root, directories: state.gameDirectories ?? [],
                      instanceDirectories: state.instances.reduce(into: [:]) { $0[$1.id] = $1.directoryID ?? GameDirectory.defaultID },
                      newInstanceDirectoryID: state.selectedDirectoryID ?? GameDirectory.defaultID,
                      instanceRunDirectories: state.instances.reduce(into: [:]) { $0[$1.id] = $1.runDirectory ?? .isolated },
                      instanceCustomDirectories: state.instances.reduce(into: [:]) { if $1.runDirectory == .custom { $0[$1.id] = $1.customRunDirectory } },
                      instanceRepositoryVersions: state.instances.reduce(into: [:]) { $0[$1.id] = $1.repositoryVersionID })
    }
    public func isMinecraftDirectory(_ id: UUID) -> Bool { directories.first(where: { $0.id == id })?.isMinecraft == true }
    public func directoryID(for instanceID: UUID) -> UUID { instanceDirectories[instanceID] ?? newInstanceDirectoryID }
    public func directoryRoot(_ id: UUID) -> URL {
        if id == GameDirectory.defaultID { return root }
        // Invalid references must never silently become the default directory.
        return directories.first(where: { $0.id == id })?.url ?? root.appendingPathComponent("unavailable-directories/\(id.uuidString)")
    }
    public func validateDirectoryConfiguration() throws {
        let ids = directories.map(\.id)
        guard root.isFileURL, Set(ids).count == ids.count, !ids.contains(GameDirectory.defaultID), directories.count <= 100,
              Set(instanceDirectories.values).union([newInstanceDirectoryID]).subtracting([GameDirectory.defaultID]).isSubset(of: Set(ids)) else { throw RuriError.message(Messages.CoreGameDirectory.invalidRegistration) }
        for directory in directories {
            _ = try GameDirectory.validName(directory.name)
            guard directory.url.isFileURL, directory.url.path.hasPrefix("/"), (directory.bookmark?.count ?? 0) <= 1_048_576 else { throw RuriError.message(Messages.CoreGameDirectory.invalidLocation) }
            try checkDirectoryOverlap(directory)
        }
        for (id, version) in instanceRepositoryVersions ?? [:] {
            try MinecraftDirectoryScan.checkIdentifier(version)
            guard isMinecraftDirectory(directoryID(for: id)) else { throw RuriError.message(Messages.CoreGameDirectory.missingMinecraftFolder) }
        }
        for (id, directory) in instanceDirectories where isMinecraftDirectory(directory) {
            guard instanceRepositoryVersions?[id] != nil else { throw RuriError.message(Messages.CoreGameDirectory.missingVersionDirectory) }
        }
        for (id, mode) in instanceRunDirectories ?? [:] where mode == .custom {
            guard let custom = instanceCustomDirectories?[id] else { throw RuriError.message(Messages.CoreGameDirectory.missingCustomRunDirectory) }
            try checkCustomRunDirectory(custom)
        }
        for (id, custom) in instanceCustomDirectories ?? [:] {
            guard instanceRunDirectories?[id] == .custom else { throw RuriError.message(Messages.CoreGameDirectory.customDirectoryMismatch) }
            for other in (instanceCustomDirectories ?? [:]).values where other.url.standardizedFileURL == custom.url.standardizedFileURL {
                guard other.id == custom.id else { throw RuriError.message(Messages.CoreGameDirectory.duplicateCustomDirectory) }
            }
        }
    }
    func checkNewDirectory(_ directory: GameDirectory) throws {
        guard directory.url.isFileURL, try directory.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message(Messages.CoreGameDirectory.requireExistingDirectory) }
        try checkDirectoryOverlap(directory)
    }
    private func checkDirectoryOverlap(_ directory: GameDirectory) throws {
        let target = directory.url.standardizedFileURL.resolvingSymlinksInPath().path
        for other in [root] + directories.filter({ $0.id != directory.id }).map(\.url) + (instanceCustomDirectories ?? [:]).values.map(\.url).filter({ !directory.isMinecraft || !$0.path.hasPrefix(target + "/") }) {
            let existing = other.standardizedFileURL.resolvingSymlinksInPath().path
            guard target != existing, !target.hasPrefix(existing + "/"), !existing.hasPrefix(target == "/" ? "/" : target + "/") else {
                throw RuriError.message(Messages.CoreGameDirectory.overlappingDirectory)
            }
        }
    }
    public func validateInstanceLocation(_ instanceID: UUID) throws {
        let id = directoryID(for: instanceID)
        if id != GameDirectory.defaultID {
            guard let directory = directories.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CoreGameDirectory.missingParentDirectory) }
            try directory.validateAvailability()
        }
        // The selected directory is trusted; its internal managed tree may not
        // escape through a symlink, including one with a not-yet-created leaf.
        let root = directoryRoot(id)
        if isMinecraftDirectory(id) {
            guard let version = instanceRepositoryVersions?[instanceID] else { throw RuriError.message(Messages.CoreGameDirectory.missingVersionFolder) }
            try MinecraftDirectoryScan.checkIdentifier(version)
            _ = try Self.safePath("versions/\(version)/\(version).json", within: root)
            _ = try Self.safePath(".ruri/instances/\(instanceID.uuidString)", within: root)
            if repositoryImportID == instanceID {
                _ = try Self.safePath(".ruri/imports/\(instanceID.uuidString)/version/\(version).json", within: root)
                _ = try Self.safePath(".ruri/imports/\(instanceID.uuidString)/metadata", within: root)
            }
        } else {
            _ = try Self.safePath("instances/\(instanceID.uuidString)/minecraft", within: root)
            if runDirectory(for: instanceID) == .shared { _ = try Self.safePath("minecraft/.ruri", within: root) }
        }
        if runDirectory(for: instanceID) == .custom {
            guard let custom = instanceCustomDirectories?[instanceID] else { throw RuriError.message(Messages.CoreGameDirectory.requireCustomDirectory) }
            try custom.validateAvailability()
            _ = try Self.safePath(".ruri", within: custom.url)
        }
    }
    public func prepareInstance(_ instanceID: UUID) throws {
        let location = try InstanceLocationLease.acquire(paths: self, instanceID: instanceID)
        defer { withExtendedLifetime(location) {} }
        try validateInstanceLocation(instanceID)
        try FileManager.default.createDirectory(at: instance(instanceID), withIntermediateDirectories: true)
    }
    /// Freeze exactly one instance's location for a detached monitor. Bookmarks
    /// are only for the launcher UI; the monitor must retain the launch path.
    func monitorSnapshot(for instanceID: UUID) -> LauncherPaths {
        let id = directoryID(for: instanceID)
        let selected = directories.filter { $0.id == id }.map { item in var item = item; item.bookmark = nil; return item }
        var custom = instanceCustomDirectories?[instanceID]; custom?.bookmark = nil
        return LauncherPaths(root: root, directories: selected, instanceDirectories: [instanceID: id], instanceRunDirectories: [instanceID: runDirectory(for: instanceID)], instanceCustomDirectories: custom.map { [instanceID: $0] }, instanceRepositoryVersions: instanceRepositoryVersions?[instanceID].map { [instanceID: $0] })
    }
}
