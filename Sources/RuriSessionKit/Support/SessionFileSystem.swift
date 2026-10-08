import Foundation
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
}
