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
