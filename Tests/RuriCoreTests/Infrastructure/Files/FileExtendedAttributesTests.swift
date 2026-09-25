import Foundation
import Testing
import Darwin
@testable import RuriCore

struct FileExtendedAttributesTests {
    static func set(_ value: Data, name: String = "org.ruri.fixture", at url: URL) throws {
        let result = value.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, value.count, 0, XATTR_NOFOLLOW) }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-attributes-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }

    @Test func streamedCopiesPreserveAttributesAndResourceForks() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try Data("data fork".utf8).write(to: source)
        try Self.set(Data("custom value".utf8), at: source)
        try Self.set(Data("resource fork".utf8), name: "com.apple.ResourceFork", at: source)
        let before = try FileExtendedAttributes.capture(source)
        try RunDirectoryFileCopy.file(source, to: target, preferClone: false) { _ in }
        #expect(try Data(contentsOf: target) == Data(contentsOf: source))
        #expect(try FileExtendedAttributes.capture(target) == before)
        #expect(before.contains { $0.name == "com.apple.ResourceFork" && $0.size == 13 })
    }

    @Test func treeCopiesPreserveDirectoryTagsAndRootAttributes() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("empty"), withIntermediateDirectories: true)
        try Data("file".utf8).write(to: source.appendingPathComponent("file"))
        let tags = try PropertyListSerialization.data(fromPropertyList: ["Ruri test\n6"], format: .binary, options: 0)
        for directory in [source, source.appendingPathComponent("empty")] { try Self.set(tags, name: "com.apple.metadata:_kMDItemUserTags", at: directory) }
        try Self.set(Data(), name: "org.ruri.empty", at: source.appendingPathComponent("file"))
        let manifest = try FileTreeManifest.capture(in: source)
        #expect(manifest.rootAttributes?.isEmpty == false)
        try RunDirectoryFileCopy.copyForPublication(source, to: target, directory: true, ignoringTransientFiles: false, created: { _ in }, validate: {}, progress: { _ in })
        try manifest.requireMatch(in: target)
        #expect(try FileExtendedAttributes.capture(target.appendingPathComponent("empty")) == FileExtendedAttributes.capture(source.appendingPathComponent("empty")))
    }

    @Test func receiptsDetectMetadataOnlyChangesWhileLegacyReceiptsRemainReadable() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        let file = source.appendingPathComponent("file"); try Data("same bytes".utf8).write(to: file)
        try Self.set(Data("old".utf8), at: file)
        let before = try FileTreeManifest.capture(in: source)
        let legacy = FileTreeManifest(version: 1, entries: before.entries.map { value in var copy = value; copy.attributes = nil; return copy })
        let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try Self.set(Data("new".utf8), at: file)
        #expect(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == date)
        #expect(throws: (any Error).self) { try before.requireMatch(in: source) }
        #expect(throws: (any Error).self) { try before.requireRemainingMatch(in: source) }
        try legacy.requireMatch(in: source)
        try Self.set(Data("old".utf8), at: file)
        try before.requireMatch(in: source)
        try Self.set(Data("root label".utf8), at: source)
        #expect(throws: (any Error).self) { try before.requireMatch(in: source) }
        let saved = root.appendingPathComponent("legacy.json"), digest = try legacy.save(to: saved)
        #expect(try FileTreeManifest.load(from: saved, expectedDigest: digest) == legacy)
    }

    @Test func stagingMetadataRewritesKeepAttributesAndRejectMalformedReceipts() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("modpack-state.json")
        try Data("before".utf8).write(to: file); try Self.set(Data("keep this label".utf8), at: file)
        let before = try FileExtendedAttributes.capture(file)
        try FileExtendedAttributes.rewrite(Data("after".utf8), at: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "after")
        #expect(try FileExtendedAttributes.capture(file) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["modpack-state.json"])
        let receipt = try #require(before.first)
        #expect(throws: (any Error).self) { try FileExtendedAttributes.validate([receipt, receipt]) }
        #expect(throws: (any Error).self) { try FileExtendedAttributes.validate([.init(name: "bad\0name", size: 0, sha256: receipt.sha256)]) }
        #expect(throws: (any Error).self) { try FileExtendedAttributes.validate([.init(name: "valid", size: .max, sha256: receipt.sha256)]) }
        #expect(throws: (any Error).self) { try FileTreeManifest(version: 2, entries: [.init(path: "file", directory: false, size: 0, sha256: receipt.sha256)]).validate() }
    }
}
