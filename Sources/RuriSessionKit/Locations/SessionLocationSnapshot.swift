import Foundation
import RuriLocalization

/// The v1 transport shape is retained, but construction freezes one instance
/// and discards UI bookmarks. No configuration store is consulted at runtime.
public struct SessionLocationSnapshot: Codable, Sendable, SessionLocationPaths {
    public let root: URL
    public let directories: [GameDirectory]
    public let instanceDirectories: [UUID: UUID]
    public let newInstanceDirectoryID: UUID
    public let instanceRunDirectories: [UUID: GameRunDirectory]?
    public let instanceCustomDirectories: [UUID: CustomRunDirectory]?
    public let instanceRepositoryVersions: [UUID: String]?

    package init(paths: any SessionLocationPaths, instanceID: UUID) {
        let directoryID = paths.directoryID(for: instanceID)
        root = paths.root
        directories = paths.directories.filter { $0.id == directoryID }.map { item in
            var item = item; item.bookmark = nil; return item
        }
        instanceDirectories = [instanceID: directoryID]
        newInstanceDirectoryID = GameDirectory.defaultID
        instanceRunDirectories = [instanceID: paths.runDirectory(for: instanceID)]
        var custom = paths.instanceCustomDirectories?[instanceID]; custom?.bookmark = nil
        instanceCustomDirectories = custom.map { [instanceID: $0] }
        instanceRepositoryVersions = paths.instanceRepositoryVersions?[instanceID].map { [instanceID: $0] }
    }

    package func validated(for instanceID: UUID) throws -> Self {
        guard instanceDirectories.count == 1, let directoryID = instanceDirectories[instanceID],
              instanceRunDirectories?.count == 1, instanceRunDirectories?[instanceID] != nil,
              newInstanceDirectoryID == GameDirectory.defaultID,
              directories.allSatisfy({ $0.id == directoryID && $0.bookmark == nil }),
              (instanceCustomDirectories ?? [:]).allSatisfy({ $0.key == instanceID && $0.value.bookmark == nil }),
              (instanceRepositoryVersions ?? [:]).keys.allSatisfy({ $0 == instanceID }) else {
            throw RuriError.message(Messages.CoreGameMonitor.invalidMonitorRequest)
        }
        try validateDirectoryConfiguration()
        try validateInstanceLocation(instanceID)
        return self
    }

    public func instance(_ id: UUID) -> URL {
        directoryRoot(directoryID(for: id))
            .appendingPathComponent(isMinecraftDirectory(directoryID(for: id)) ? ".ruri/instances" : "instances")
            .appendingPathComponent(id.uuidString)
    }
    public func game(_ id: UUID) -> URL {
        if runDirectory(for: id) == .custom {
            return instanceCustomDirectories?[id]?.url ?? root.appendingPathComponent("unavailable-run-directories/\(id.uuidString)")
        }
        if isMinecraftDirectory(directoryID(for: id)) {
            return runDirectory(for: id) == .isolated
                ? directoryRoot(directoryID(for: id)).appendingPathComponent("versions").appendingPathComponent(instanceRepositoryVersions?[id] ?? "unavailable-\(id.uuidString)")
                : directoryRoot(directoryID(for: id))
        }
        return (runDirectory(for: id) == .isolated ? instance(id) : directoryRoot(directoryID(for: id))).appendingPathComponent("minecraft")
    }
    package func gameDataState(_ id: UUID) -> URL {
        runDirectory(for: id) == .isolated ? instance(id) : game(id).appendingPathComponent(".ruri")
    }
}
