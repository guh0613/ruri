import RuriLocalization
import Foundation
import Darwin

/// Used under each manager's in-process recursive lock. The OS lock also keeps
/// a second launcher from treating an in-flight transaction as crash recovery.
final class GameDataOperationLock {
    private var depth = 0
    private var descriptor: Int32?
    func acquire(directory: URL, name: String) throws {
        if depth > 0 { depth += 1; return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = try LauncherPaths.safePath(name, within: directory)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreGameDataOperationLock.fdText1) }
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            close(fd); throw RuriError.message(Messages.CoreGameDataOperationLock.infoText1)
        }
        descriptor = fd; depth = 1
    }
    func release() {
        depth -= 1
        if depth == 0, let descriptor { close(descriptor); self.descriptor = nil }
    }
    deinit { if let descriptor { close(descriptor) } }
}
