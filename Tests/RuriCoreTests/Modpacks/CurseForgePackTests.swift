import Foundation
import Testing
@testable import RuriCore

struct CurseForgePackTests {
    let fixture = CurseForgeTests()
    func setup(overrides: String = "overrides", files: [[String: Any]] = [["projectID": 1, "fileID": 10, "required": true], ["projectID": 2, "fileID": 20, "required": false]], loaders: [String] = ["fabric-0.19.5"]) throws -> (LauncherPaths, URL) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        let pack = paths.cache.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
        let manifest: [String: Any] = ["manifestType": "minecraftModpack", "manifestVersion": 1, "name": "Pack 测试", "author": "Fixture", "version": "1.0",
            "minecraft": ["version": "1.21.1", "modLoaders": loaders.map { ["id": $0, "primary": true] as [String: Any] }], "files": files, "overrides": overrides]
        try fixture.json(manifest).write(to: pack.appendingPathComponent("manifest.json"))
        return (paths, pack)
    }
    func content(_ paths: LauncherPaths, id: Int = 10, project: Int = 1) throws -> ContentInstallation {
        let file = try fixture.decoded(fixture.file(id, project: project))
        let project = try JSONDecoder().decode(CurseForgeProject.self, from: fixture.json(fixture.project(project)))
        let source = paths.cache.appendingPathComponent(file.fileName); try fixture.body.write(to: source)
        return .init(record: PlannedCurseFile(project: project, file: file, kind: .mod).record, source: source)
    }
    @Test func emptyOverridesAndOptionalFilesImportWithoutChangingManifest() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        #expect(preview.format == "CurseForge"); #expect(preview.instance.loader == .fabric)
        #expect(preview.fileCount == 0); #expect(preview.curseForgeFiles.count == 2)
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("overrides").path))
        let item = try content(paths)
        let imported = try await transfer.install(preview, name: "Imported", content: [item]) { instance in
            let installedData = try Data(contentsOf: paths.game(instance.id).appendingPathComponent("mods/mod-10.jar"))
            #expect(installedData == fixture.body)
            var result = instance; result.installed = true; return result
        }
        #expect(imported.installed)
        let records = try await ContentManager(paths: paths, instanceID: imported.id).records()
        #expect(records.count == 1); #expect(records.first?.versionID == "10")
        await transfer.discard(preview)
    }
    @Test func missingOrCorruptFilesFailBeforeGameInstallAndFailureRollsBack() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        await #expect(throws: (any Error).self) { try await transfer.install(preview, name: "Missing") { _ in Issue.record("Installer must not run"); throw RuriError.message("unreachable") } }
        let item = try content(paths); try Data("modified".utf8).write(to: item.source)
        await #expect(throws: (any Error).self) { try await transfer.install(preview, name: "Corrupt", content: [item]) { _ in Issue.record("Installer must not run"); throw RuriError.message("unreachable") } }
        try fixture.body.write(to: item.source)
        await #expect(throws: (any Error).self) { try await transfer.install(preview, name: "Failure", content: [item]) { _ in throw RuriError.message("Simulated network failure") } }
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.instances.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: preview.game.path))
        await transfer.discard(preview)
    }
    @Test func bundledOverridesWinAndChangedModsStayUnmanaged() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let override = source.appendingPathComponent("overrides/mods/mod-10.jar")
        try FileManager.default.createDirectory(at: override.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("custom pack file".utf8).write(to: override)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        let imported = try await transfer.install(preview, name: "Custom", content: [content(paths)]) { $0 }
        #expect(try Data(contentsOf: paths.game(imported.id).appendingPathComponent("mods/mod-10.jar")) == Data("custom pack file".utf8))
        #expect(try await ContentManager(paths: paths, instanceID: imported.id).records().isEmpty)
        await transfer.discard(preview)
    }
    @Test func unsafeOverridesDuplicateProjectsAndUnsupportedLoadersAreRejected() async throws {
        for (overrides, refs, loaders) in [
            ("../outside", [["projectID": 1, "fileID": 10]], ["fabric-0.19.5"]),
            ("overrides", [["projectID": 1, "fileID": 10], ["projectID": 1, "fileID": 11]], ["forge-52.1.16"]),
            ("overrides", [], ["unknown-1"]), ("overrides", [], ["fabric-1", "forge-2"])
        ] {
            let (paths, source) = try setup(overrides: overrides, files: refs, loaders: loaders)
            defer { try? FileManager.default.removeItem(at: paths.root) }
            await #expect(throws: (any Error).self) { try await InstanceTransfer(paths: paths).prepare(source) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: paths.cache.path).filter { $0.hasPrefix("transfer-") }.isEmpty)
        }
    }
    @Test func manualCacheSurvivesOriginalRemovalAndRejectsWrongVersions() async throws {
        let (paths, _) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let original = paths.cache.appendingPathComponent("download.jar")
        let file = try fixture.decoded(fixture.file(10, project: 1))
        try Data("other version".utf8).write(to: original)
        await #expect(throws: (any Error).self) { try await CurseForgeService.cacheManualFile(original, file: file, paths: paths) }
        try fixture.body.write(to: original)
        let cached = try await CurseForgeService.cacheManualFile(original, file: file, paths: paths)
        try FileManager.default.removeItem(at: original)
        #expect(try Data(contentsOf: cached) == fixture.body)
        #expect(cached.lastPathComponent == file.fileName)
    }
}
