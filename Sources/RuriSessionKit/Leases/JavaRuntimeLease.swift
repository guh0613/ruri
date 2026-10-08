import RuriLocalization
import Foundation
import Darwin

/// Games and installer processes hold a shared lease. Repair/removal holds an
/// exclusive lease outside the runtime directory that is about to be replaced.
public final class JavaRuntimeLease: @unchecked Sendable {
    private let descriptor: Int32
    private init(_ descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }
    package static func managedID(binary: URL, paths: any SessionPaths) -> String? {
        let root = paths.root.appendingPathComponent("runtimes").standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let file = binary.standardizedFileURL.resolvingSymlinksInPath().path
        guard file.hasPrefix(root), let folder = file.dropFirst(root.count).split(separator: "/").first else { return nil }
        let id = String(folder)
        return id.hasPrefix(".partial-") ? String(id.dropFirst(9)) : id.hasPrefix(".") ? nil : id
    }
    package static func shared(binary: URL, paths: any SessionPaths) throws -> JavaRuntimeLease? {
        guard let id = managedID(binary: binary, paths: paths) else { return nil }
        return try acquire(id: id, paths: paths, exclusive: false)
    }
    package static func acquire(id: String, paths: any SessionPaths, exclusive: Bool) throws -> JavaRuntimeLease {
        guard !id.isEmpty, !id.hasPrefix("."), !id.contains("/"), !id.contains("\\"), !id.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuriError.message(Messages.CoreJavaRuntimeLease.invalidJavaRuntimeName) }
        let directory = try SessionFileSystem.safePath(".locks", within: paths.root.appendingPathComponent("runtimes"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockFile = try SessionFileSystem.safePath(id + ".lock", within: directory)
        let fd = open(lockFile.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreJavaRuntimeLease.javaRuntimeLockFailed) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { close(fd); throw RuriError.message(Messages.CoreJavaRuntimeLease.invalidJavaRuntimeLock) }
        var value = flock(); value.l_type = Int16(exclusive ? F_WRLCK : F_RDLCK); value.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_OFD_SETLK, &value) == 0 else { close(fd); throw RuriError.message(Messages.CoreJavaRuntimeLease.javaRuntimeInUse) }
        return JavaRuntimeLease(fd)
    }
    package static func requireNoRunningProcess(in directory: URL) throws {
        let bytes = proc_listallpids(nil, 0)
        guard bytes > 0 else { return }
        var pids = [Int32](repeating: 0, count: Int(bytes) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        let prefix = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        for pid in pids.prefix(max(0, Int(count))) where pid > 0 && ProcessIdentity.read(pid) != nil {
            var buffer = [CChar](repeating: 0, count: 4096)
            let size = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            if size > 0 {
                let executable = String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
                if executable.hasPrefix(prefix) { throw RuriError.message(Messages.CoreJavaRuntimeLease.javaRuntimeUsedByProcess(String(describing: pid))) }
            }
        }
    }
}
