import Foundation
import CryptoKit
import Darwin

/// A portable content receipt: file identities and modification times can differ
/// across volumes, while equal sizes and dates alone cannot prove a complete copy.
struct FileTreeManifest: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let path: String
        let directory: Bool
        let size: Int64
        let sha256: String?
    }
    let version: Int
    let entries: [Entry]
    static let maximumRecordBytes = 64 * 1024 * 1024
    static let maximumFileBytes: Int64 = 128 * 1024 * 1024 * 1024

    static func capture(in root: URL, excluding: Set<String> = [], ignoringTransientFiles: Bool = false) throws -> Self {
        let before = try FileTree.entries(in: root, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles)
        let result = try capture(before)
        guard try FileTree.entries(in: root, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles) == before else {
            throw RuriError.message("校验期间目录内容改变，请重试。")
        }
        return result
    }

    /// Entries may come from several source roots and use mapped destination
    /// paths. Include their implicit parents so a staged tree compares equally.
    static func capture(_ files: [FileTree.Entry], requiringDirectories: Set<String> = []) throws -> Self {
        guard files.count <= 150_000 else { throw RuriError.message("待校验文件数量超过限制。") }
        var result: [String: Entry] = [:], bytes: Int64 = 0
        for file in files {
            try Task.checkCancellation(); try validatePath(file.path)
            guard result[file.path] == nil else { throw RuriError.message("待校验的文件路径重复：\(file.path)") }
            if !file.directory {
                guard file.size >= 0, file.size <= maximumFileBytes - bytes else { throw RuriError.message("待校验文件大小超过限制。") }
                bytes += file.size
            }
            result[file.path] = .init(path: file.path, directory: file.directory, size: file.directory ? 0 : file.size,
                                      sha256: file.directory ? nil : try digest(file.url, expectedSize: file.size))
        }
        let required = Set((Set(result.keys).union(requiringDirectories)).flatMap { parents($0) }).union(requiringDirectories)
        for path in required {
            try validatePath(path)
            if let entry = result[path] {
                guard entry.directory else { throw RuriError.message("文件与目录路径冲突：\(path)") }
            } else { result[path] = .init(path: path, directory: true, size: 0, sha256: nil) }
        }
        let manifest = Self(version: 1, entries: result.values.sorted { $0.path < $1.path })
        try manifest.validate(); return manifest
    }

    func requireMatch(in root: URL, excluding: Set<String> = [], ignoringTransientFiles: Bool = false) throws {
        try validate()
        guard try Self.capture(in: root, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles) == self else {
            throw RuriError.message("文件内容与校验记录不一致，原文件和工作副本已保留，请核对后重试。")
        }
    }

    /// After source deletion has started, missing original entries are expected.
    /// Every remaining entry must still belong to the original content receipt.
    func requireRemainingMatch(in root: URL) throws {
        try validate()
        let expected = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        let remaining = try Self.capture(in: root)
        guard remaining.entries.allSatisfy({ expected[$0.path] == $0 }) else {
            throw RuriError.message("原文件清理期间出现新增或改变的内容，剩余文件已保留。")
        }
    }

    func save(to file: URL) throws -> String {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumRecordBytes else { throw RuriError.message("文件校验记录超过大小限制。") }
        try data.write(to: file, options: .atomic)
        return Self.digest(data)
    }
    static func load(from file: URL, expectedDigest: String) throws -> Self {
        guard validDigest(expectedDigest) else { throw RuriError.message("文件校验记录摘要无效。") }
        let data = try RunDirectoryCopyGuard.read(file, limit: maximumRecordBytes)
        guard digest(data) == expectedDigest else { throw RuriError.message("文件校验记录已经改变，未清理原文件或工作副本。") }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        try manifest.validate(); return manifest
    }

    func validate() throws {
        guard version == 1, entries.count <= 150_000 else { throw RuriError.message("文件校验记录版本或数量无效。") }
        var seen: [String: Bool] = [:], bytes: Int64 = 0
        for entry in entries {
            try Self.validatePath(entry.path)
            guard seen[entry.path] == nil, entry.size >= 0, entry.size <= Self.maximumFileBytes - bytes else { throw RuriError.message("文件校验记录包含重复路径或无效大小。") }
            if entry.directory {
                guard entry.size == 0, entry.sha256 == nil else { throw RuriError.message("目录校验记录无效。") }
            } else {
                guard entry.sha256.map(Self.validDigest) == true else { throw RuriError.message("文件校验摘要无效。") }
                bytes += entry.size
            }
            seen[entry.path] = entry.directory
        }
        for entry in entries {
            guard Self.parents(entry.path).allSatisfy({ seen[$0] == true }) else { throw RuriError.message("文件校验记录缺少父目录或路径冲突。") }
        }
        guard entries.map(\.path) == entries.map(\.path).sorted() else { throw RuriError.message("文件校验记录顺序无效。") }
    }

    static func validDigest(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private static func validatePath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 4096, !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw RuriError.message("文件校验记录包含无效路径。") }
    }
    private static func parents(_ path: String) -> [String] {
        let parts = path.split(separator: "/")
        return parts.indices.dropFirst().map { parts[..<$0].joined(separator: "/") }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func digest(_ file: URL, expectedSize: Int64) throws -> String {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message("无法校验文件：\(file.lastPathComponent)") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size == expectedSize else { throw RuriError.message("待校验文件类型或大小改变。") }
        var hash = SHA256(), remaining = expectedSize
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: Int(min(1_048_576, remaining))) ?? Data()
            guard !data.isEmpty else { throw RuriError.message("校验期间文件长度改变。") }
            hash.update(data: data); remaining -= Int64(data.count)
        }
        try Task.checkCancellation()
        var after = stat(), location = stat()
        guard fstat(fd, &after) == 0, lstat(file.path, &location) == 0,
              unchanged(before, after), unchanged(before, location) else { throw RuriError.message("校验期间文件被修改或替换。") }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}
