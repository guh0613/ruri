import RuriLocalization
import Foundation
import CryptoKit
import Darwin

enum DownloadFileLock {
    /// An open-file-description lock covers separate managers and processes.
    /// Closing the returned descriptor releases it, including after a crash.
    static func acquire(for destination: URL) async throws -> Int32 {
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        let name = parent.appendingPathComponent(destination.lastPathComponent).path
        let key = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = parent.appendingPathComponent(".ruri-partials")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message(Messages.CoreDownloadFileLock.downloadCacheSymlink) }
        let path = directory.appendingPathComponent(key + ".lock").path
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreDownloadFileLock.downloadFileLockFailed(destination.lastPathComponent)) }
        do {
            while true {
                try Task.checkCancellation()
                var lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET); lock.l_len = 0
                if fcntl(fd, F_OFD_SETLK, &lock) == 0 { return fd }
                guard errno == EAGAIN || errno == EACCES else { throw RuriError.message(Messages.CoreDownloadFileLock.downloadFileLockUnavailable(destination.lastPathComponent)) }
                try await Task.sleep(for: .milliseconds(50))
            }
        } catch { close(fd); throw error }
    }
}
