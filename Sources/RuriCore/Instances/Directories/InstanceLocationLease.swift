import RuriLocalization
import Foundation
import Darwin

/// This lock lives outside the movable instance tree. Readers may run normal
/// game/file operations together; a move upgrades to an exclusive writer before
/// it can retire the original tree and its per-directory locks.
public final class InstanceLocationLease: @unchecked Sendable {
    private let lease: SessionLocationLease
    private init(_ lease: SessionLocationLease) { self.lease = lease }

    public static func acquire(paths: LauncherPaths, instanceID: UUID) throws -> InstanceLocationLease {
        let result = try openLease(paths: paths, instanceID: instanceID, exclusive: false)
        try InstanceMoveGuard.requireAvailable(paths: paths, instanceID: instanceID)
        try requireCurrentDirectory(paths: paths, instanceID: instanceID)
        return result
    }

    /// Recovery checks the persisted transaction's source and target itself.
    /// It must not recreate either tree just to obtain an operation lock.
    static func acquireForMoveRecovery(paths: LauncherPaths, instanceID: UUID) throws -> InstanceLocationLease {
        try openLease(paths: paths, instanceID: instanceID, exclusive: true)
    }

    func excludeOtherOperations() throws { try lease.excludeOtherOperations() }

    static func requireCurrentDirectory(paths: LauncherPaths, instanceID: UUID) throws {
        try ModpackUpdateStore.requireAvailable(paths: paths, instanceID: instanceID)
        if paths.repositoryImportID != instanceID, SessionOperation.repositoryImport.hasPending(paths: paths, instanceID: instanceID) {
            throw RuriError.message(Messages.CoreInstanceLocationLease.requireCurrentDirectory)
        }
        let state = try StateStore.load(paths)
        guard !(state.detachedMinecraftFolders ?? []).contains(where: { folder in folder.instances.contains(where: { $0.id == instanceID }) }) else {
            throw RuriError.message(Messages.CoreInstanceLocationLease.folderRemoved)
        }
        // New installations and import snapshots may not be registered yet.
        guard let instance = state.instances.first(where: { $0.id == instanceID }) else { return }
        guard (instance.directoryID ?? GameDirectory.defaultID) == paths.directoryID(for: instanceID) else {
            throw RuriError.message(Messages.CoreInstanceLocationLease.instanceMoved)
        }
    }

    private static func openLease(paths: LauncherPaths, instanceID: UUID, exclusive: Bool) throws -> InstanceLocationLease {
        InstanceLocationLease(try SessionLocationLease.acquire(paths: paths, instanceID: instanceID, exclusive: exclusive))
    }

}

/// Mirrors the recursive file-operation scope in ContentManager/WorldManager.
final class InstanceLocationOperationLock {
    private var lease: InstanceLocationLease?
    private var depth = 0
    func acquire(paths: LauncherPaths, instanceID: UUID) throws {
        if depth == 0 { lease = try InstanceLocationLease.acquire(paths: paths, instanceID: instanceID) }
        depth += 1
    }
    func release() {
        depth -= 1
        if depth == 0 { lease = nil }
    }
}
