import Foundation
import Darwin
import RuriLocalization

package final class SessionLocationLease: @unchecked Sendable {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }
    package func excludeOtherOperations() throws { try Self.lock(descriptor, exclusive: true) }
    package static func acquire(paths: any SessionPaths, instanceID: UUID, exclusive: Bool) throws -> SessionLocationLease {
        let directory = try SessionFileSystem.safePath("instance-location-locks", within: paths.root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try SessionFileSystem.safePath(instanceID.uuidString + ".lock", within: directory)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreInstanceLocationLease.lockFailed) }
        let result = SessionLocationLease(fd)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw RuriError.message(Messages.CoreInstanceLocationLease.lockNotRegularFile) }
        try lock(fd, exclusive: exclusive)
        return result
    }

    private static func lock(_ fd: Int32, exclusive: Bool) throws {
        var lock = flock(); lock.l_type = Int16(exclusive ? F_WRLCK : F_RDLCK); lock.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_OFD_SETLK, &lock) == 0 else { throw RuriError.message(Messages.CoreInstanceLocationLease.operationInProgress) }
    }
}
