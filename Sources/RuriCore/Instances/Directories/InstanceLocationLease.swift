import RuriLocalization
import Foundation
import Darwin

/// This lock lives outside the movable instance tree. Readers may run normal
/// game/file operations together; a move upgrades to an exclusive writer before
/// it can retire the original tree and its per-directory locks.
public final class InstanceLocationLease: @unchecked Sendable {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

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

    func excludeOtherOperations() throws { try Self.lock(descriptor, exclusive: true) }

    static func requireCurrentDirectory(paths: LauncherPaths, instanceID: UUID) throws {
        try ModpackUpdateStore.requireAvailable(paths: paths, instanceID: instanceID)
        if paths.repositoryImportID != instanceID, paths.isMinecraftDirectory(paths.directoryID(for: instanceID)),
           FileManager.default.fileExists(atPath: paths.repositoryImportWorkspace(instanceID).path) {
            throw RuriError.message(Messages.CoreInstanceLocationLease.requireCurrentDirectoryText1)
        }
        let state = try StateStore.load(paths)
        guard !(state.detachedMinecraftFolders ?? []).contains(where: { folder in folder.instances.contains(where: { $0.id == instanceID }) }) else {
            throw RuriError.message(Messages.CoreInstanceLocationLease.stateText1)
        }
        // New installations and import snapshots may not be registered yet.
        guard let instance = state.instances.first(where: { $0.id == instanceID }) else { return }
        guard (instance.directoryID ?? GameDirectory.defaultID) == paths.directoryID(for: instanceID) else {
            throw RuriError.message(Messages.CoreInstanceLocationLease.instanceText1)
        }
    }

    private static func openLease(paths: LauncherPaths, instanceID: UUID, exclusive: Bool) throws -> InstanceLocationLease {
        let directory = try LauncherPaths.safePath("instance-location-locks", within: paths.root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try LauncherPaths.safePath(instanceID.uuidString + ".lock", within: directory)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreInstanceLocationLease.fdText1) }
        let result = InstanceLocationLease(fd)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreInstanceLocationLease.infoText1) }
        try lock(fd, exclusive: exclusive)
        return result
    }

    private static func lock(_ fd: Int32, exclusive: Bool) throws {
        var lock = flock(); lock.l_type = Int16(exclusive ? F_WRLCK : F_RDLCK); lock.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_OFD_SETLK, &lock) == 0 else { throw RuriError.message(Messages.CoreInstanceLocationLease.lockText1) }
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
