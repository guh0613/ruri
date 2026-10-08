import Foundation
import Darwin
import RuriLocalization

/// Only the kernel lock. Registration and transaction policy belongs to Core;
/// a monitor may use these locks solely to resume its designated session.
package final class SessionRunFileLease: @unchecked Sendable {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    package static func instance(at directory: URL) throws -> SessionRunFileLease {
        let file = try SessionFileSystem.safePath(".ruri-game.lock", within: directory)
        return try acquire(file, unavailable: Messages.CoreGameRunLease.runLockUnavailable,
                           busy: Messages.CoreGameRunLease.instanceAlreadyRunning)
    }
    package static func shared(at root: URL) throws -> SessionRunFileLease {
        let metadata = try SessionFileSystem.safePath(".ruri", within: root)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        return try acquire(SessionFileSystem.safePath("run.lock", within: metadata),
                           unavailable: Messages.CoreSharedGameDirectoryLease.lockFailed,
                           busy: Messages.CoreSharedGameDirectoryLease.directoryInUse)
    }
    private static func acquire(_ file: URL, unavailable: LocalizedMessage, busy: LocalizedMessage) throws -> SessionRunFileLease {
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(unavailable) }
        let result = SessionRunFileLease(fd)
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            throw RuriError.message(busy)
        }
        return result
    }
}
