import Foundation
import Testing
import Darwin
@testable import RuriCore

struct FileTreeManifestTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-file-verification-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func write(_ text: String, to root: URL, path: String) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    @Test func contentReceiptsSurviveCopyAndDetectEqualSizeEditsWithRestoredDates() throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("source"), target = base.appendingPathComponent("target")
        try write("abc", to: source, path: "saves/世界/data.txt")
        try write("", to: source, path: "empty-file")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("empty-directory"), withIntermediateDirectories: true)
        let original = try FileTreeManifest.capture(in: source)
        try FileManager.default.copyItem(at: source, to: target)
        try original.requireMatch(in: target)
        let record = base.appendingPathComponent("verification.json"), digest = try original.save(to: record)
        #expect(try FileTreeManifest.load(from: record, expectedDigest: digest) == original)
        let changed = target.appendingPathComponent("saves/世界/data.txt")
        let date = try changed.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try Data("xyz".utf8).write(to: changed)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: changed.path) }
        #expect(throws: (any Error).self) { try original.requireMatch(in: target) }
        try Data("abc".utf8).write(to: changed)
        try original.requireMatch(in: target)
        try write("added", to: target, path: "extra.txt")
        #expect(throws: (any Error).self) { try original.requireMatch(in: target) }
        try FileManager.default.removeItem(at: target.appendingPathComponent("extra.txt"))
        try FileManager.default.removeItem(at: target.appendingPathComponent("empty-directory"))
        #expect(throws: (any Error).self) { try original.requireMatch(in: target) }
    }

    @Test func fullReceiptsIncludeNormallyExcludedFilesAndMappedParents() throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        try write("finder", to: base, path: ".DS_Store")
        try write("unfinished", to: base, path: ".ruri-partials/keep.bin")
        try write("data", to: base, path: "file.txt")
        let full = try FileTreeManifest.capture(in: base)
        #expect(full.entries.contains { $0.path == ".ruri-partials/keep.bin" })
        #expect(full.entries.contains { $0.path == ".DS_Store" })
        let portable = try FileTreeManifest.capture(in: base, ignoringTransientFiles: true)
        #expect(portable.entries.map(\.path) == ["file.txt"])
        let files = try FileTree.entries(in: base).map { FileTree.Entry(url: $0.url, path: "minecraft/" + $0.path, directory: $0.directory, size: $0.size, modified: $0.modified) }
        let mapped = try FileTreeManifest.capture(files, requiringDirectories: ["empty/nested"])
        #expect(mapped.entries.map(\.path) == ["empty", "empty/nested", "minecraft", "minecraft/file.txt"])
    }

    @Test func malformedAndChangedRecordsAreRejected() throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        try write("data", to: base, path: "file.txt")
        let good = try FileTreeManifest.capture(in: base)
        let record = base.appendingPathComponent("record.json"), digest = try good.save(to: record)
        try Data("{}".utf8).write(to: record)
        #expect(throws: (any Error).self) { try FileTreeManifest.load(from: record, expectedDigest: digest) }
        try FileManager.default.removeItem(at: record)
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: base.appendingPathComponent("file.txt"))
        #expect(throws: (any Error).self) { try FileTreeManifest.load(from: record, expectedDigest: digest) }
        for path in ["../outside", "/absolute", "a//b", "a/./b", "a\\b", "a\0b"] {
            let bad = FileTreeManifest(version: 1, entries: [.init(path: path, directory: true, size: 0, sha256: nil)])
            #expect(throws: (any Error).self) { try bad.validate() }
        }
        let entry = try #require(good.entries.first)
        for bad in [FileTreeManifest(version: 3, entries: []), FileTreeManifest(version: 1, entries: [entry, entry]),
                    FileTreeManifest(version: 1, entries: [.init(path: "a/b", directory: true, size: 0, sha256: nil)]),
                    FileTreeManifest(version: 1, entries: [.init(path: "a", directory: false, size: .max, sha256: entry.sha256)]),
                    FileTreeManifest(version: 1, entries: [.init(path: "a", directory: false, size: 0, sha256: "invalid")])] {
            #expect(throws: (any Error).self) { try bad.validate() }
        }
    }

    @Test func symbolicLinksAndFIFOsAreRejectedWithoutFollowingOrBlocking() throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        try write("original", to: base, path: "source/file.txt")
        let source = base.appendingPathComponent("source"), link = source.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: base)
        #expect(throws: (any Error).self) { try FileTreeManifest.capture(in: source) }
        try FileManager.default.removeItem(at: link)
        let files = try FileTree.entries(in: source)
        let file = source.appendingPathComponent("file.txt")
        try FileManager.default.removeItem(at: file)
        #expect(mkfifo(file.path, S_IRUSR | S_IWUSR) == 0)
        #expect(throws: (any Error).self) { try FileTreeManifest.capture(files) }
    }

    @Test func hashingCanBeCancelled() async throws {
        let base = try root(); defer { try? FileManager.default.removeItem(at: base) }
        try write(String(repeating: "a", count: 2_000_000), to: base, path: "large.bin")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try FileTreeManifest.capture(in: base)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}
