import Darwin
import Foundation
import RuriLocalization

/// A reference is not a copy. Finished runs require the same file identity,
/// size and modification time, so a new latest.log can never impersonate it.
public struct GameLogReference: Codable, Equatable, Sendable {
    public let relativePath: String
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64

    package init(relativePath: String, info: stat) {
        self.relativePath = relativePath; device = UInt64(UInt32(bitPattern: info.st_dev)); inode = UInt64(info.st_ino)
        size = info.st_size; modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
    }
    package var modifiedAt: Date { Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000) }
    package func matches(_ info: stat, growing: Bool = false) -> Bool {
        device == UInt64(UInt32(bitPattern: info.st_dev)) && inode == UInt64(info.st_ino) &&
        (growing ? info.st_size >= size : info.st_size == size && Int64(info.st_mtimespec.tv_sec) == modifiedSeconds && Int64(info.st_mtimespec.tv_nsec) == modifiedNanoseconds)
    }
    package func validate() throws {
        guard GameSession.safeRelativePath(relativePath), relativePath.utf8.count <= 2048, size >= 0,
              (0..<1_000_000_000).contains(modifiedNanoseconds),
              relativePath == "logs/latest.log" || relativePath == "logs/debug.log" ||
              (relativePath.hasPrefix("crash-reports/crash-") && relativePath.hasSuffix(".txt")) ||
              (relativePath.hasPrefix("hs_err_pid") && relativePath.hasSuffix(".log")) else { throw POSIXError(.EINVAL) }
    }
}
