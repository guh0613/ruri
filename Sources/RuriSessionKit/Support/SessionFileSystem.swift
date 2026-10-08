import Foundation
import Darwin
import RuriLocalization

public enum SessionFileSystem {
    public static func safePath(_ path: String, within root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { throw RuriError.message(Messages.CoreLauncherPaths.unsafeFilePath(path)) }
        let baseURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let base = baseURL.path + "/"
        var resolved = baseURL
        // Foundation does not resolve an intermediate symlink reliably when the
        // final file does not exist yet. Validate each existing prefix instead.
        for component in path.split(separator: "/") where component != "." {
            resolved = resolved.appendingPathComponent(String(component)).standardizedFileURL
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: resolved.path)) != nil {
                resolved = resolved.resolvingSymlinksInPath()
            }
            guard resolved.path.hasPrefix(base) else { throw RuriError.message(Messages.CoreLauncherPaths.pathOutsideInstanceDirectory(path)) }
        }
        return resolved
    }
    package static func checkVersionIdentifier(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 255, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuriError.message(Messages.CoreMinecraftVersionMetadata.invalidInheritancePath) }
    }
    package static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.recordReadFailed(url.path)) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= limit else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.invalidRecordFile) }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.sizeLimit) }
        return data
    }
}
