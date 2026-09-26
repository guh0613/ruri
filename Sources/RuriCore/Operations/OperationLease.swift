import RuriLocalization
import Foundation
import Darwin

/// A nonblocking cross-process lease; never hold the state lock while waiting
/// for a network request. The descriptor releases ownership on process exit.
public final class OperationLease: Sendable {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    public static func acquire(directory: URL, name: String) throws -> OperationLease {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = try LauncherPaths.safePath(name, within: directory)
        let fd = open(path.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw OperationFailure("LOCK_UNAVAILABLE", Messages.CLIInterface.teff59600ae41.localized) }
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            close(fd); throw OperationFailure("RESOURCE_BUSY", Messages.CLIInterface.tce7693c68759.localized, retryable: true)
        }
        return OperationLease(fd)
    }
    deinit { close(descriptor) }
}
