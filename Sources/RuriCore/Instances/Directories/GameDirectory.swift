import Foundation
import RuriLocalization

extension GameDirectory {
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

    public func relocated(to url: URL, paths: LauncherPaths) throws -> GameDirectory {
        var result = self; result.url = url.standardizedFileURL.resolvingSymlinksInPath()
        try result.validateAvailability()
        try paths.checkNewDirectory(result)
        result.bookmark = try result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return result
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
    func checkNewDirectory(_ directory: GameDirectory) throws {
        guard directory.url.isFileURL, try directory.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message(Messages.CoreGameDirectory.requireExistingDirectory) }
        try checkDirectoryOverlap(directory)
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
