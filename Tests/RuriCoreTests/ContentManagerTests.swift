import Testing
import Foundation
import CryptoKit
@testable import RuriCore

struct ContentManagerTests {
    func setup() throws -> (LauncherPaths, UUID, ContentManager) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try paths.prepare(); let id = UUID()
        return (paths, id, ContentManager(paths: paths, instanceID: id))
    }
    func plan(_ paths: LauncherPaths, project: String = "example", version: String, file: String, text: String, dependencies: [String] = []) throws -> ContentInstallation {
        let data = Data(text.utf8)
        let source = paths.cache.appendingPathComponent(UUID().uuidString)
        try data.write(to: source)
        let hash = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ContentInstallation(record: ManagedContent(projectID: project, versionID: version, title: "Example", versionName: version, kind: .mod, filename: file, sha1: hash, size: Int64(data.count), requiredProjects: dependencies), source: source)
    }
    @Test func updatesReplaceOldFilenameAndPreserveDisabledState() async throws {
        let (paths, id, manager) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try await manager.install([plan(paths, version: "1", file: "example-1.jar", text: "first")])
        let original = try #require(await manager.scan(.mod).first)
        try await manager.setEnabled(false, file: original)
        try await manager.install([plan(paths, version: "2", file: "example-2.jar", text: "second")])
        #expect(!FileManager.default.fileExists(atPath: paths.game(id).appendingPathComponent("mods/example-1.jar.disabled").path))
        #expect(try Data(contentsOf: paths.game(id).appendingPathComponent("mods/example-2.jar.disabled")) == Data("second".utf8))
        let current = try #require(await manager.scan(.mod).first)
        #expect(!current.enabled)
        #expect(current.managed?.versionID == "2")
        try await manager.setEnabled(true, file: current)
        #expect(try await manager.scan(.mod).first?.enabled == true)
    }
    @Test func rejectsModifiedFilesBeforeChangingAnything() async throws {
        let (paths, id, manager) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try await manager.install([plan(paths, version: "1", file: "one.jar", text: "original")])
        let original = paths.game(id).appendingPathComponent("mods/one.jar")
        try Data("modified".utf8).write(to: original)
        await #expect(throws: (any Error).self) { try await manager.install([plan(paths, version: "2", file: "two.jar", text: "upgrade")]) }
        #expect(try Data(contentsOf: original) == Data("modified".utf8))
        #expect(!FileManager.default.fileExists(atPath: paths.game(id).appendingPathComponent("mods/two.jar").path))
        #expect(try await manager.records().first?.versionID == "1")
    }
    @Test func rejectsFilenameCollisionsAndProtectsDependencies() async throws {
        let (paths, _, manager) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        await #expect(throws: (any Error).self) {
            try await manager.install([plan(paths, project: "a", version: "1", file: "same.jar", text: "a"), plan(paths, project: "b", version: "1", file: "same.jar", text: "b")])
        }
        #expect(try await manager.records().isEmpty)
        try await manager.install([plan(paths, project: "api", version: "1", file: "api.jar", text: "api"), plan(paths, project: "mod", version: "1", file: "mod.jar", text: "mod", dependencies: ["api"])])
        let files = try await manager.scan(.mod)
        let api = try #require(files.first { $0.filename == "api.jar" })
        await #expect(throws: (any Error).self) { try await manager.setEnabled(false, file: api) }
        let dependent = try #require(files.first { $0.filename == "mod.jar" })
        try await manager.setEnabled(false, file: dependent)
        try await manager.setEnabled(false, file: api)
        let disabled = try #require(await manager.scan(.mod).first { $0.filename == "mod.jar" })
        await #expect(throws: (any Error).self) { try await manager.setEnabled(true, file: disabled) }
    }
    @Test func interruptedCommitRecoversOriginalFilesAndMetadata() async throws {
        let (paths, id, manager) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let first = try plan(paths, version: "1", file: "old.jar", text: "old")
        try await manager.install([first])
        let transaction = paths.instance(id).appendingPathComponent("content-transaction")
        let backups = transaction.appendingPathComponent("backups/mods")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: backups.appendingPathComponent("old.jar"))
        let journal = ContentManager.Journal(affected: ["mods/old.jar", "mods/new.jar"], originals: ["mods/old.jar"], oldRecords: [first.record])
        try JSONEncoder().encode(journal).write(to: transaction.appendingPathComponent("journal.json"))
        try FileManager.default.removeItem(at: paths.game(id).appendingPathComponent("mods/old.jar"))
        try Data("incomplete".utf8).write(to: paths.game(id).appendingPathComponent("mods/new.jar"))
        try Data("[]".utf8).write(to: paths.instance(id).appendingPathComponent("content.json"))
        try await manager.recover()
        #expect(try Data(contentsOf: paths.game(id).appendingPathComponent("mods/old.jar")) == Data("old".utf8))
        #expect(!FileManager.default.fileExists(atPath: paths.game(id).appendingPathComponent("mods/new.jar").path))
        #expect(try await manager.records() == [first.record])
    }
    @Test func missingRecoveryBackupDoesNotDeleteCurrentFile() async throws {
        let (paths, id, manager) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let first = try plan(paths, version: "1", file: "old.jar", text: "original")
        try await manager.install([first])
        let tx = paths.instance(id).appendingPathComponent("content-transaction")
        try FileManager.default.createDirectory(at: tx, withIntermediateDirectories: true)
        let journal = ContentManager.Journal(affected: ["mods/old.jar"], originals: ["mods/old.jar"], oldRecords: [first.record])
        try JSONEncoder().encode(journal).write(to: tx.appendingPathComponent("journal.json"))
        await #expect(throws: (any Error).self) { try await manager.recover() }
        #expect(try Data(contentsOf: paths.game(id).appendingPathComponent("mods/old.jar")) == Data("original".utf8))
    }
    @Test func rejectsContentSymlinksEvenWhenTheyStayInsideInstance() async throws {
        let (paths, id, manager) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let saves = paths.game(id).appendingPathComponent("saves")
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Data("world".utf8).write(to: saves.appendingPathComponent("important.jar"))
        try FileManager.default.createSymbolicLink(at: paths.game(id).appendingPathComponent("mods"), withDestinationURL: saves)
        await #expect(throws: (any Error).self) { try await manager.install([plan(paths, version: "1", file: "important.jar", text: "mod")]) }
        #expect(try Data(contentsOf: saves.appendingPathComponent("important.jar")) == Data("world".utf8))
    }
}
