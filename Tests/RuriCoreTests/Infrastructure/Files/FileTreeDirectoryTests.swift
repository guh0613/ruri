import Foundation
import Testing
import Darwin
@testable import RuriCore

struct FileTreeDirectoryTests {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-directory-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false); return root
    }

    @Test func ordinaryDotUnderscoreFilesAndDirectoriesArePreserved() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["._manual", "paired", "._paired", "._folder/nested"] {
            let file = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("ordinary user data".utf8).write(to: file)
        }
        #expect(Set(try FileTree.entries(in: root).map(\.path)) == ["._manual", "paired", "._paired", "._folder", "._folder/nested"])
        try FileExtendedAttributesTests.set(Data("native attributes still matter".utf8), at: root.appendingPathComponent("._manual"))
        let receipt = try FileTreeManifest.capture(in: root)
        #expect(receipt.entries.first { $0.path == "._manual" }?.attributes?.contains { $0.name == "org.ruri.fixture" } == true)
    }

    @Test func onlyMetadataRepresentedOnTheCompanionCanBeOmitted() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file"), sidecar = root.appendingPathComponent("._file")
        try Data("data fork".utf8).write(to: file)
        try FileExtendedAttributesTests.set(Data("custom metadata".utf8), at: file)
        try FileExtendedAttributesTests.set(Data("resource fork".utf8), name: "com.apple.ResourceFork", at: file)
        #expect(copyfile(file.path, sidecar.path, nil, copyfile_flags_t(COPYFILE_PACK | COPYFILE_XATTR | COPYFILE_EXCL)) == 0)
        #expect(try FileTree.entries(in: root).map(\.path) == ["file"])
        try FileExtendedAttributesTests.set(Data("changed metadata".utf8), at: file)
        #expect(Set(try FileTree.entries(in: root).map(\.path)) == ["file", "._file"])
        try FileManager.default.removeItem(at: file)
        #expect(try FileTree.entries(in: root).map(\.path) == ["._file"])
    }

    @Test func malformedAndUnrecognizedAppleDoubleLayoutsRemainOrdinaryFiles() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file"), sidecar = root.appendingPathComponent("._file")
        try Data("data".utf8).write(to: file)
        try FileExtendedAttributesTests.set(Data("value".utf8), at: file)
        #expect(copyfile(file.path, sidecar.path, nil, copyfile_flags_t(COPYFILE_PACK | COPYFILE_XATTR | COPYFILE_EXCL)) == 0)
        let original = try Data(contentsOf: sidecar)
        for range in [24..<26, 34..<38, 92..<96, 96..<100, 118..<120, 124..<128] {
            var changed = original
            changed.replaceSubrange(range, with: repeatElement(UInt8.max, count: range.count))
            try changed.write(to: sidecar)
            #expect(Set(try FileTree.entries(in: root).map(\.path)) == ["file", "._file"])
        }
    }
}
