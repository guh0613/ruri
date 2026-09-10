import Foundation
import Darwin

/// Open-file-description locks survive object handoffs but are never inherited
/// by Java. The monitor holds one for the whole game lifetime.
public final class GameRunLease: @unchecked Sendable {
    private let descriptor: Int32
    private let sharedDirectory: SharedGameDirectoryLease?
    private init(_ descriptor: Int32, sharedDirectory: SharedGameDirectoryLease?) { self.descriptor = descriptor; self.sharedDirectory = sharedDirectory }
    deinit { Darwin.close(descriptor) }
    public static func acquire(paths: LauncherPaths, instanceID: UUID, ignoringSession: UUID? = nil, directoryChangeID: UUID? = nil) throws -> GameRunLease {
        try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID, allowing: directoryChangeID)
        try paths.prepareInstance(instanceID)
        let file = try LauncherPaths.safePath(".ruri-game.lock", within: paths.instance(instanceID))
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message("无法取得实例运行锁。") }
        var lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET); lock.l_len = 0
        guard fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            Darwin.close(fd); throw RuriError.message("这个实例正在运行或准备启动，请先结束当前游戏。")
        }
        var shared: SharedGameDirectoryLease?
        do {
            try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID, allowing: directoryChangeID)
            if paths.runDirectory(for: instanceID) != .isolated { shared = try SharedGameDirectoryLease.acquire(paths: paths, instanceID: instanceID, ignoringSession: ignoringSession, directoryChangeID: directoryChangeID) }
            let records = try GameSessionStore.list(paths: paths, instanceID: instanceID)
            guard !records.contains(where: { $0.id != ignoringSession && !$0.state.isFinished && GameMonitorClient.activity($0) != .inactive }) else {
                throw RuriError.message("这个实例仍有活动或状态未确认的运行会话，请先检查运行记录。")
            }
        } catch { Darwin.close(fd); throw error }
        return GameRunLease(fd, sharedDirectory: shared)
    }
    func reserve(paths: LauncherPaths, session: GameSession) throws { try sharedDirectory?.reserve(paths: paths, session: session) }
    func clearReservation(session: GameSession) throws { try sharedDirectory?.clearReservation(session: session) }
    public static func isHeld(paths: LauncherPaths, instanceID: UUID) -> Bool {
        guard (try? paths.validateInstanceLocation(instanceID)) != nil else { return true }
        if RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: instanceID) { return true }
        if InstanceCopyGuard.hasPending(paths: paths, instanceID: instanceID) { return true }
        if paths.runDirectory(for: instanceID) != .isolated, SharedGameDirectoryLease.isHeld(paths: paths, instanceID: instanceID) { return true }
        guard let file = try? LauncherPaths.safePath(".ruri-game.lock", within: paths.instance(instanceID)) else { return true }
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let fd = open(file.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return true }
        defer { Darwin.close(fd) }
        var lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET); lock.l_len = 0
        return fcntl(fd, F_OFD_SETLK, &lock) != 0
    }
}
