import Foundation
import Darwin

/// A PID alone may refer to an unrelated process after the original has exited.
public struct ProcessIdentity: Codable, Equatable, Sendable {
    public enum Liveness: Sendable { case alive, exited, unverifiable }
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64
    public static func read(_ pid: Int32) -> ProcessIdentity? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size,
              info.pbi_uid == getuid(), info.pbi_status != UInt32(SZOMB) else { return nil }
        return ProcessIdentity(pid: pid, startSeconds: info.pbi_start_tvsec, startMicroseconds: info.pbi_start_tvusec)
    }
    public var liveness: Liveness {
        guard pid > 0 else { return .exited }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else {
            // A permission or transient inspection error is not proof of exit.
            return kill(pid, 0) != 0 && errno == ESRCH ? .exited : .unverifiable
        }
        if info.pbi_status == UInt32(SZOMB) || info.pbi_start_tvsec != startSeconds || info.pbi_start_tvusec != startMicroseconds { return .exited }
        return info.pbi_uid == getuid() ? .alive : .unverifiable
    }
    public var isAlive: Bool { liveness == .alive }
}

/// Open-file-description locks survive object handoffs but are never inherited
/// by Java. The monitor holds one for the whole game lifetime.
public final class GameRunLease: @unchecked Sendable {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }
    public static func acquire(paths: LauncherPaths, instanceID: UUID, ignoringSession: UUID? = nil) throws -> GameRunLease {
        try FileManager.default.createDirectory(at: paths.instance(instanceID), withIntermediateDirectories: true)
        let file = try LauncherPaths.safePath(".ruri-game.lock", within: paths.instance(instanceID))
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message("无法取得实例运行锁。") }
        var lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET); lock.l_len = 0
        guard fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            Darwin.close(fd); throw RuriError.message("这个实例正在运行或准备启动，请先结束当前游戏。")
        }
        do {
            let records = try GameSessionStore.list(paths: paths, instanceID: instanceID)
            guard !records.contains(where: { $0.id != ignoringSession && !$0.state.isFinished && GameMonitorClient.activity($0) != .inactive }) else {
                throw RuriError.message("这个实例仍有活动或状态未确认的运行会话，请先检查运行记录。")
            }
        } catch { Darwin.close(fd); throw error }
        return GameRunLease(fd)
    }
    public static func isHeld(paths: LauncherPaths, instanceID: UUID) -> Bool {
        guard let file = try? LauncherPaths.safePath(".ruri-game.lock", within: paths.instance(instanceID)) else { return true }
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let fd = open(file.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return true }
        defer { Darwin.close(fd) }
        var lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET); lock.l_len = 0
        return fcntl(fd, F_OFD_SETLK, &lock) != 0
    }
}
