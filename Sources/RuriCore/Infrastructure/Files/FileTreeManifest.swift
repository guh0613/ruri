import RuriLocalization
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
        var attributes: [FileExtendedAttributes.Receipt]? = nil
    }
    let version: Int
    let entries: [Entry]
    var rootAttributes: [FileExtendedAttributes.Receipt]? = nil
    static let maximumRecordBytes = 64 * 1024 * 1024
    static let maximumFileBytes: Int64 = 128 * 1024 * 1024 * 1024

    static func capture(in root: URL, excluding: Set<String> = [], ignoringTransientFiles: Bool = false) throws -> Self {
        let before = try FileTree.entries(in: root, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles)
        let attributes = try FileExtendedAttributes.capture(root)
        let result = try capture(before, rootAttributes: attributes)
        guard try FileTree.entries(in: root, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles) == before,
              try FileExtendedAttributes.capture(root) == attributes else {
            throw RuriError.message(Messages.CoreFileTreeManifest.resultText1)
        }
        return result
    }

    /// Entries may come from several source roots and use mapped destination
    /// paths. Include their implicit parents so a staged tree compares equally.
    static func capture(_ files: [FileTree.Entry], requiringDirectories: Set<String> = [], rootAttributes: [FileExtendedAttributes.Receipt]? = nil) throws -> Self {
        guard files.count <= 150_000 else { throw RuriError.message(Messages.CoreFileTreeManifest.captureText1) }
        var result: [String: Entry] = [:], bytes: Int64 = 0
        for file in files {
            try Task.checkCancellation(); try validatePath(file.path)
            guard result[file.path] == nil else { throw RuriError.message(Messages.CoreFileTreeManifest.resultText2(String(describing: file.path))) }
            if !file.directory {
                guard file.size >= 0, file.size <= maximumFileBytes - bytes else { throw RuriError.message(Messages.CoreFileTreeManifest.resultText3) }
                bytes += file.size
            }
            let attributes = try FileExtendedAttributes.capture(file.url)
            result[file.path] = .init(path: file.path, directory: file.directory, size: file.directory ? 0 : file.size,
                                      sha256: file.directory ? nil : try digest(file.url, expectedSize: file.size), attributes: attributes)
            guard try FileExtendedAttributes.capture(file.url) == attributes else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText1) }
        }
        let required = Set((Set(result.keys).union(requiringDirectories)).flatMap { parents($0) }).union(requiringDirectories)
        for path in required {
            try validatePath(path)
            if let entry = result[path] {
                guard entry.directory else { throw RuriError.message(Messages.CoreFileTreeManifest.entryText1(String(describing: path))) }
            } else { result[path] = .init(path: path, directory: true, size: 0, sha256: nil, attributes: []) }
        }
        let manifest = Self(version: 2, entries: result.values.sorted { $0.path < $1.path }, rootAttributes: rootAttributes)
        try manifest.validate(); return manifest
    }

    func requireMatch(in root: URL, excluding: Set<String> = [], ignoringTransientFiles: Bool = false) throws {
        try validate()
        guard try Self.capture(in: root, excluding: excluding, ignoringTransientFiles: ignoringTransientFiles).matchingFormat(of: self) == self else {
            throw RuriError.message(Messages.CoreFileTreeManifest.requireMatchText1)
        }
    }

    /// After source deletion has started, missing original entries are expected.
    /// Every remaining entry must still belong to the original content receipt.
    func requireRemainingMatch(in root: URL) throws {
        try validate()
        let expected = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        let remaining = try Self.capture(in: root).matchingFormat(of: self)
        guard remaining.rootAttributes == rootAttributes, remaining.entries.allSatisfy({ expected[$0.path] == $0 }) else {
            throw RuriError.message(Messages.CoreFileTreeManifest.remainingText1)
        }
    }

    func save(to file: URL) throws -> String {
        try validate()
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumRecordBytes else { throw RuriError.message(Messages.CoreFileTreeManifest.dataText1) }
        try data.write(to: file, options: .atomic)
        return Self.digest(data)
    }
    static func load(from file: URL, expectedDigest: String) throws -> Self {
        guard validDigest(expectedDigest) else { throw RuriError.message(Messages.CoreFileTreeManifest.loadText1) }
        let data = try RunDirectoryCopyGuard.read(file, limit: maximumRecordBytes)
        guard digest(data) == expectedDigest else { throw RuriError.message(Messages.CoreFileTreeManifest.dataText2) }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        try manifest.validate(); return manifest
    }

    func validate() throws {
        guard (1...2).contains(version), entries.count <= 150_000 else { throw RuriError.message(Messages.CoreFileTreeManifest.validateText1) }
        if let rootAttributes { guard version >= 2 else { throw RuriError.message(Messages.CoreFileTreeManifest.rootAttributesText1) }; try FileExtendedAttributes.validate(rootAttributes) }
        var seen: [String: Bool] = [:], bytes: Int64 = 0
        for entry in entries {
            try Self.validatePath(entry.path)
            if version >= 2 {
                guard let attributes = entry.attributes else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText2) }
                try FileExtendedAttributes.validate(attributes)
            } else if entry.attributes != nil { throw RuriError.message(Messages.CoreFileTreeManifest.rootAttributesText1) }
            guard seen[entry.path] == nil, entry.size >= 0, entry.size <= Self.maximumFileBytes - bytes else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText3) }
            if entry.directory {
                guard entry.size == 0, entry.sha256 == nil else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText4) }
            } else {
                guard entry.sha256.map(Self.validDigest) == true else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText5) }
                bytes += entry.size
            }
            seen[entry.path] = entry.directory
        }
        for entry in entries {
            guard Self.parents(entry.path).allSatisfy({ seen[$0] == true }) else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText6) }
        }
        guard entries.map(\.path) == entries.map(\.path).sorted() else { throw RuriError.message(Messages.CoreFileTreeManifest.attributesText7) }
    }

    static func validDigest(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private func matchingFormat(of receipt: Self) -> Self {
        Self(version: receipt.version, entries: entries.map { entry in
            var value = entry; if receipt.version == 1 { value.attributes = nil }; return value
        }, rootAttributes: receipt.rootAttributes == nil ? nil : rootAttributes)
    }
    private static func validatePath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 4096, !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { throw RuriError.message(Messages.CoreFileTreeManifest.validatePathText1) }
    }
    private static func parents(_ path: String) -> [String] {
        let parts = path.split(separator: "/")
        return parts.indices.dropFirst().map { parts[..<$0].joined(separator: "/") }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func digest(_ file: URL, expectedSize: Int64) throws -> String {
        let fd = open(file.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message(Messages.CoreFileTreeManifest.fdText1(String(describing: file.lastPathComponent))) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size == expectedSize else { throw RuriError.message(Messages.CoreFileTreeManifest.beforeText1) }
        var hash = SHA256(), remaining = expectedSize
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: Int(min(1_048_576, remaining))) ?? Data()
            guard !data.isEmpty else { throw RuriError.message(Messages.CoreFileTreeManifest.dataText3) }
            hash.update(data: data); remaining -= Int64(data.count)
        }
        try Task.checkCancellation()
        var after = stat(), location = stat()
        guard fstat(fd, &after) == 0, lstat(file.path, &location) == 0,
              unchanged(before, after), unchanged(before, location) else { throw RuriError.message(Messages.CoreFileTreeManifest.afterText1) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func unchanged(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode && a.st_size == b.st_size &&
        a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec &&
        a.st_ctimespec.tv_sec == b.st_ctimespec.tv_sec && a.st_ctimespec.tv_nsec == b.st_ctimespec.tv_nsec
    }
}
