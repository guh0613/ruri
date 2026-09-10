import Foundation
import Darwin

extension FileTree {
    /// Foundation hides every dot-underscore name on some removable volumes,
    /// including ordinary user files. Enumerate actual directory entries and
    /// omit only recognized AppleDouble companions represented by native xattrs.
    static func children(in directory: URL) throws -> [URL] {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw RuriError.message("无法读取目录：\(directory.lastPathComponent)") }
        guard let stream = fdopendir(fd) else { close(fd); throw RuriError.message("无法枚举目录：\(directory.lastPathComponent)") }
        defer { closedir(stream) }
        var names: [String] = []
        while true {
            try Task.checkCancellation(); errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw RuriError.message("读取目录时发生错误。") }; break
            }
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: length + 1) { String(validatingCString: $0) }
            }
            guard let name else { throw RuriError.message("目录包含无法表示的文件名，原文件已保留。") }
            if name != "." && name != ".." { names.append(name) }
            guard names.count <= 150_000 else { throw RuriError.message("目录文件数量超过限制。") }
        }
        let all = Set(names)
        return try names.sorted().compactMap { name in
            let url = directory.appending(component: name, directoryHint: .notDirectory)
            if name.hasPrefix("._"), all.contains(String(name.dropFirst(2))),
               try FileAppleDouble.isRepresented(url, by: directory.appending(component: String(name.dropFirst(2)))) { return nil }
            return url
        }
    }

}
