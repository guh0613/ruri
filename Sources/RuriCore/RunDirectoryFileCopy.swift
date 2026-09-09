import Foundation
import Darwin

enum RunDirectoryFileCopy {
    /// APFS clones are independent files, not hard links. Other filesystems
    /// fall back to bounded chunks so cancellation can interrupt a large file.
    static func file(_ source: URL, to target: URL, preferClone: Bool = true, progress: (Int64) -> Void) throws {
        let inputFD = open(source.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard inputFD >= 0 else { throw RuriError.message("无法读取待复制文件：\(source.lastPathComponent)") }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true); defer { try? input.close() }
        var info = stat()
        guard fstat(inputFD, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw RuriError.message("复制源不是普通文件。") }
        try Task.checkCancellation()
        if preferClone, fclonefileat(inputFD, AT_FDCWD, target.path, UInt32(CLONE_NOOWNERCOPY | CLONE_ACL)) == 0 { progress(info.st_size); return }
        let outputFD = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard outputFD >= 0 else { throw RuriError.message("无法创建复制副本：\(target.lastPathComponent)") }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true); defer { try? output.close() }
        var copied: Int64 = 0
        while copied < info.st_size {
            try Task.checkCancellation()
            let bytes = try input.read(upToCount: Int(min(1_048_576, info.st_size - copied))) ?? Data()
            guard !bytes.isEmpty else { throw RuriError.message("复制期间源文件长度改变。") }
            try output.write(contentsOf: bytes); copied += Int64(bytes.count); progress(Int64(bytes.count))
        }
        try output.synchronize()
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        try FileManager.default.setAttributes([.posixPermissions: info.st_mode & 0o777, .modificationDate: attributes[.modificationDate] ?? Date()], ofItemAtPath: target.path)
    }
    static func entries(_ entries: [FileTree.Entry], to root: URL, validate: () throws -> Void, progress: (Int64, Bool) -> Void) throws {
        try validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for entry in entries {
            try Task.checkCancellation()
            try validate()
            let target = try LauncherPaths.safePath(entry.path, within: root)
            if entry.directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file(entry.url, to: target) { progress($0, false) }
                progress(0, true)
            }
        }
        for entry in entries.reversed() where entry.directory {
            try validate()
            let target = try LauncherPaths.safePath(entry.path, within: root)
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.url.path)
            try FileManager.default.setAttributes([.posixPermissions: attributes[.posixPermissions] ?? 0o755, .modificationDate: entry.modified], ofItemAtPath: target.path)
        }
    }
    static func moveWithoutReplacing(_ source: URL, to target: URL) throws {
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else { throw RuriError.message("无法发布或收回复制项目，目标可能已存在或磁盘位置发生变化：\(target.lastPathComponent)") }
    }
}
