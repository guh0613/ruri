import RuriLocalization
import Foundation
import ZIPFoundation

public enum FileTree {
    struct Entry: Equatable, Sendable { let url: URL; let path: String; let directory: Bool; let size: Int64; let modified: Date }
    static func entries(in root: URL, excluding: Set<String> = [], ignoringTransientFiles: Bool = true) throws -> [Entry] {
        guard try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message(Messages.CoreFileTree.entriesText1) }
        var pending: [(URL, String)] = [(root, "")]; var entries: [Entry] = []
        while let (directory, prefix) = pending.popLast() {
            try Task.checkCancellation()
            for url in try children(in: directory) {
                let relative = prefix + url.lastPathComponent
                if (ignoringTransientFiles && [".DS_Store", ".ruri-partials"].contains(url.lastPathComponent)) || excluding.contains(relative) || excluding.contains(where: { $0.hasSuffix("/") && relative.hasPrefix($0) }) { continue }
                let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard info.isSymbolicLink != true else { throw RuriError.message(Messages.CoreFileTree.infoText1(String(describing: relative))) }
                guard info.isDirectory == true || info.isRegularFile == true else { throw RuriError.message(Messages.CoreFileTree.infoText2(String(describing: relative))) }
                entries.append(Entry(url: url, path: relative, directory: info.isDirectory == true, size: Int64(info.fileSize ?? 0), modified: info.contentModificationDate ?? .distantPast))
                guard entries.count <= 150_000 else { throw RuriError.message(Messages.CoreFileTree.infoText3) }
                if info.isDirectory == true { pending.append((url, relative + "/")) }
            }
        }
        return entries
    }
    public static func copy(from source: URL, to destination: URL, excluding: Set<String> = [], progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws {
        let sourcePath = source.resolvingSymlinksInPath().standardizedFileURL.path
        let destinationPath = destination.resolvingSymlinksInPath().standardizedFileURL.path
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else { throw RuriError.message(Messages.CoreFileTree.destinationPathText1) }
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
        guard try Self.entries(in: source, excluding: excluding) == entries else { throw RuriError.message(Messages.CoreFileTree.targetText1) }
    }
    /// Used only on an import snapshot, where a later pack layer deliberately
    /// wins. Source entries and destination prefixes are checked before copying.
    static func overlay(from source: URL, to destination: URL, excluding: Set<String> = []) throws {
        let entries = try entries(in: source, excluding: excluding)
        for entry in entries {
            try Task.checkCancellation()
            let target = try LauncherPaths.safePath(entry.path, within: destination)
            if FileManager.default.fileExists(atPath: target.path) {
                let directory = try target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
                if entry.directory && directory { continue }
                try FileManager.default.removeItem(at: target)
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if entry.directory { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
            else { try FileManager.default.copyItem(at: entry.url, to: target) }
        }
        guard try Self.entries(in: source, excluding: excluding) == entries else { throw RuriError.message(Messages.CoreFileTree.directoryText1) }
    }
}

extension SafeArchive {
    public static func create(from source: URL, to destination: URL, prefix: String = "", additionalFiles: [String: Data] = [:], excluding: Set<String> = [], progress: @Sendable (Int, Int) -> Void = { _, _ in }) throws {
        let root = source.resolvingSymlinksInPath().standardizedFileURL.path
        guard !destination.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root + "/") else { throw RuriError.message(Messages.CoreFileTree.rootText1) }
        let entries = try FileTree.entries(in: source, excluding: excluding)
        let prefix = prefix.isEmpty ? "" : prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        func check(_ path: String) throws {
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else { throw RuriError.message(Messages.CoreFileTree.checkText1(String(describing: path))) }
        }
        var names = Set<String>()
        if !prefix.isEmpty { let directory = String(prefix.dropLast()); try check(directory); names.insert(directory) }
        for name in entries.map({ prefix + $0.path }) + Array(additionalFiles.keys) {
            try check(name)
            guard names.insert(name).inserted else { throw RuriError.message(Messages.CoreFileTree.directoryText2(String(describing: name))) }
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let archive = try Archive(url: staging, accessMode: .create)
            // Keep the game root even when it has no files yet. Portable
            // instance readers need it to distinguish a valid empty instance.
            if !prefix.isEmpty { try archive.addEntry(with: prefix, type: .directory, uncompressedSize: Int64(0)) { _, _ in Data() } }
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
                        guard let data = try handle.read(upToCount: count), data.count == count else { throw RuriError.message(Messages.CoreFileTree.dataText1(String(describing: entry.path))) }
                        return data
                    }
                    let current = try entry.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    guard current.fileSize == Int(entry.size), current.contentModificationDate == entry.modified else { throw RuriError.message(Messages.CoreFileTree.dataText1(String(describing: entry.path))) }
                }
                progress(index + 1, entries.count)
            }
            for (path, data) in additionalFiles.sorted(by: { $0.key < $1.key }) {
                try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, count in data.subdata(in: Int(position)..<(Int(position) + count)) }
            }
        }
        let current = try FileTree.entries(in: source, excluding: excluding)
        guard current.count == entries.count, zip(current, entries).allSatisfy({ $0.path == $1.path && $0.size == $1.size && $0.modified == $1.modified }) else { throw RuriError.message(Messages.CoreFileTree.currentText1) }
        try verify(staging, maxBytes: 128 * 1024 * 1024 * 1024)
        try Task.checkCancellation()
        guard rename(staging.path, destination.path) == 0 else { throw RuriError.message(Messages.CoreFileTree.currentText2(String(describing: destination.lastPathComponent))) }
    }
}
