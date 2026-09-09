import Foundation
import ZIPFoundation

public enum FileTree {
    struct Entry: Equatable { let url: URL; let path: String; let directory: Bool; let size: Int64; let modified: Date }
    static func entries(in root: URL, excluding: Set<String> = []) throws -> [Entry] {
        let fm = FileManager.default
        guard try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message("请选择实际目录，而不是符号链接。") }
        var pending: [(URL, String)] = [(root, "")]; var entries: [Entry] = []
        while let (directory, prefix) = pending.popLast() {
            try Task.checkCancellation()
            for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let relative = prefix + url.lastPathComponent
                if url.lastPathComponent == ".DS_Store" || excluding.contains(relative) || excluding.contains(where: { $0.hasSuffix("/") && relative.hasPrefix($0) }) { continue }
                let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard info.isSymbolicLink != true else { throw RuriError.message("目录包含符号链接，无法完整复制：\(relative)") }
                guard info.isDirectory == true || info.isRegularFile == true else { throw RuriError.message("不支持的文件类型：\(relative)") }
                entries.append(Entry(url: url, path: relative, directory: info.isDirectory == true, size: Int64(info.fileSize ?? 0), modified: info.contentModificationDate ?? .distantPast))
                guard entries.count <= 150_000 else { throw RuriError.message("目录文件数量超过限制") }
                if info.isDirectory == true { pending.append((url, relative + "/")) }
            }
        }
        return entries
    }
    public static func copy(from source: URL, to destination: URL, excluding: Set<String> = [], progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else { throw RuriError.message("目标目录不能位于源目录内") }
        let entries = try entries(in: source, excluding: excluding)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let target = try LauncherPaths.safePath(entry.path, within: destination)
            if entry.directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else {
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: entry.url, to: target)
            }
            progress(index + 1, entries.count)
        }
        guard try Self.entries(in: source, excluding: excluding) == entries else { throw RuriError.message("源目录在复制期间发生了变化，请退出游戏后重试。") }
    }
}

extension SafeArchive {
    public static func create(from source: URL, to destination: URL, prefix: String = "", additionalFiles: [String: Data] = [:], excluding: Set<String> = [], progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws {
        let root = source.resolvingSymlinksInPath().standardizedFileURL.path
        guard !destination.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root + "/") else { throw RuriError.message("压缩包不能保存在源目录内") }
        let entries = try FileTree.entries(in: source, excluding: excluding)
        let prefix = prefix.isEmpty ? "" : prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        func check(_ path: String) throws {
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { throw RuriError.message("无效压缩包路径：\(path)") }
        }
        var names = Set<String>()
        for name in entries.map({ prefix + $0.path }) + Array(additionalFiles.keys) {
            try check(name)
            guard names.insert(name).inserted else { throw RuriError.message("压缩包条目重名：\(name)") }
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let archive = try Archive(url: staging, accessMode: .create)
            for (index, entry) in entries.enumerated() {
                try Task.checkCancellation()
                let path = prefix + entry.path
                if entry.directory { try archive.addEntry(with: path + "/", type: .directory, uncompressedSize: Int64(0)) { _, _ in Data() } }
                else {
                    let handle = try FileHandle(forReadingFrom: entry.url)
                    defer { try? handle.close() }
                    try archive.addEntry(with: path, type: .file, uncompressedSize: entry.size, modificationDate: entry.modified, compressionMethod: .deflate, bufferSize: 128 * 1024) { position, count in
                        try Task.checkCancellation(); try handle.seek(toOffset: UInt64(position))
                        if count == 0 { return Data() }
                        guard let data = try handle.read(upToCount: count), data.count == count else { throw RuriError.message("备份期间源文件发生变化：\(entry.path)") }
                        return data
                    }
                    let current = try entry.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    guard current.fileSize == Int(entry.size), current.contentModificationDate == entry.modified else { throw RuriError.message("备份期间源文件发生变化：\(entry.path)") }
                }
                progress(index + 1, entries.count)
            }
            for (path, data) in additionalFiles.sorted(by: { $0.key < $1.key }) {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, count in data.subdata(in: Int(position)..<(Int(position) + count)) }
            }
        }
        let current = try FileTree.entries(in: source, excluding: excluding)
        guard current.count == entries.count, zip(current, entries).allSatisfy({ $0.path == $1.path && $0.size == $1.size && $0.modified == $1.modified }) else { throw RuriError.message("源目录在备份期间发生了变化，请退出游戏后重试。") }
        try verify(staging, maxBytes: 128 * 1024 * 1024 * 1024)
        try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw RuriError.message("无法保存压缩包：\(destination.lastPathComponent)") }
    }
}
