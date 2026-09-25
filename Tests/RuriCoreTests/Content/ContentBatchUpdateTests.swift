import Foundation
import Testing
@testable import RuriCore

struct ContentBatchUpdateTests {
    private func version(_ id: String, project: String, dependencies: [ModrinthVersion.Dependency] = []) -> ModrinthVersion {
        ModrinthVersion(id: id, project_id: project, name: project, version_number: id, date_published: "2026-09-11T00:00:00Z", version_type: "release",
                        files: [.init(url: URL(string: "https://files.test/\(id).jar")!, filename: id + ".jar", primary: true, size: 5, hashes: ["sha1": "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"])],
                        dependencies: dependencies, game_versions: ["1.21.1"], loaders: ["fabric"])
    }
    private func write(_ data: Data, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }
    private func fixture() throws -> (LauncherPaths, GameInstance, ContentManager) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try paths.prepare()
        var instance = GameInstance(name: "Batch", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.19.5")
        instance.installed = true
        var state = try StateStore.load(paths); state.instances = [instance]; try StateStore.save(state, to: paths)
        return (paths, instance, ContentManager(paths: paths, instanceID: instance.id))
    }

    @Test func mixedProviderUpdatesCommitTogetherAndRetainDisabledState() async throws {
        let (paths, instance, manager) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let cf = CurseForgeTests(), helper = ContentManagerTests()
        let project = try JSONDecoder().decode(CurseForgeProject.self, from: cf.json(cf.project(1, allowed: false)))
        let oldCF = PlannedCurseFile(project: project, file: try cf.decoded(cf.file(9, project: 1)), kind: .mod)
        let cfSource = paths.cache.appendingPathComponent("old-cf.jar"); try write(cf.body, to: cfSource)
        try await manager.install([
            helper.plan(paths, project: "a", version: "a1", file: "a1.jar", text: "old mod"),
            helper.plan(paths, project: "dep", version: "d1", file: "d1.jar", text: "hello"),
            ContentInstallation(record: oldCF.record, source: cfSource)
        ])
        let aFile = try #require(await manager.scan(.mod).first { $0.managed?.projectID == "a" })
        try await manager.setEnabled(false, file: aFile)
        let baseline = try await manager.records()
        let a = try #require(baseline.first { $0.projectID == "a" }), dep = try #require(baseline.first { $0.projectID == "dep" })
        let server = EndpointHTTPFixture([
            "api.curseforge.com/v1/mods/1": try cf.json(["data": cf.project(1, allowed: false)]),
            "api.curseforge.com/v1/mods/2": try cf.json(["data": cf.project(2)]),
            "api.curseforge.com/v1/mods/2/files": try cf.json(["data": [cf.file(20, project: 2)]])
        ])
        defer { server.close() }
        let updater = ContentBatchUpdater(modrinth: ModrinthService(client: HTTPClient(session: server.session)), curseforge: CurseForgeService(apiKey: "fixture", client: HTTPClient(session: server.session)))
        let plan = try await updater.prepare(modrinth: [
            ContentUpdate(installed: a, available: version("a2", project: "a", dependencies: [.init(version_id: nil, project_id: "dep", dependency_type: "required")])),
            ContentUpdate(installed: dep, available: version("d2", project: "dep"))
        ], curseforge: [CurseForgeUpdate(installed: oldCF.record, available: try cf.decoded(cf.file(10, project: 1, dependencies: [["modId": 2, "relationType": 3]])))], instance: instance, paths: paths)
        // An unavailable download must leave the installed files untouched.
        let downloader = DownloadManager(configuration: server.session.configuration, retryDelay: .zero)
        await #expect(throws: (any Error).self) { try await updater.install(plan, paths: paths, downloader: downloader) { _ in } }
        #expect(try await manager.records() == baseline)
        #expect(try Data(contentsOf: aFile.url.appendingPathExtension("disabled")) == Data("old mod".utf8))
        for item in plan.modrinth { try write(Data("hello".utf8), to: paths.cache.appendingPathComponent("modrinth/\(item.record.versionID)/\(item.file.filename)")) }
        for item in plan.curseforge { try write(cf.body, to: paths.cache.appendingPathComponent("curseforge/\(item.id)/\(item.file.fileName)")) }
        let manual = paths.cache.appendingPathComponent("curseforge/10/mod-10.jar")
        try await updater.install(plan, paths: paths, downloader: downloader, manualFiles: [10: manual]) { _ in }
        let files = try await manager.scan(.mod)
        #expect(Set(files.map(\.filename)) == ["a2.jar", "d2.jar", "mod-10.jar", "mod-20.jar"])
        let updated = try #require(files.first { $0.managed?.projectID == "a" })
        #expect(updated.url.lastPathComponent == "a2.jar.disabled")
        #expect(try Data(contentsOf: updated.url) == Data("hello".utf8))
        #expect(files.first { $0.managed?.projectID == "dep" }?.managed?.versionID == "d2")
        #expect(files.contains { $0.managed?.provider == "curseforge" && $0.managed?.versionID == "10" })
    }

    @Test func stalePreviewAndConflictingDependenciesLeaveAllFilesIntact() async throws {
        let (paths, instance, manager) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let helper = ContentManagerTests()
        try await manager.install([helper.plan(paths, project: "a", version: "a1", file: "a1.jar", text: "hello"), helper.plan(paths, project: "b", version: "b1", file: "b1.jar", text: "hello")])
        let original = try await manager.records(), server = EndpointHTTPFixture([:])
        defer { server.close() }
        let service = ModrinthService(client: HTTPClient(session: server.session))
        let updater = ContentBatchUpdater(modrinth: service, curseforge: CurseForgeService(apiKey: ""))
        let plan = try await updater.prepare(modrinth: original.map { ContentUpdate(installed: $0, available: version($0.projectID + "2", project: $0.projectID)) }, curseforge: [], instance: instance, paths: paths)
        for item in plan.modrinth { try write(Data("hello".utf8), to: paths.cache.appendingPathComponent("modrinth/\(item.record.versionID)/\(item.file.filename)")) }
        let first = try #require(await manager.scan(.mod).first)
        try await manager.setEnabled(false, file: first)
        let changed = try await manager.records()
        await #expect(throws: (any Error).self) { try await updater.install(plan, paths: paths, downloader: DownloadManager()) { _ in } }
        #expect(try await manager.records() == changed)
        #expect(try await manager.scan(.mod).allSatisfy { ["a1.jar", "b1.jar"].contains($0.filename) })
        let incompatible = version("a2", project: "a", dependencies: [.init(version_id: nil, project_id: "b", dependency_type: "incompatible")])
        await #expect(throws: (any Error).self) { try await service.plan(versions: [incompatible, version("b2", project: "b")], kind: .mod, instance: instance) }
        await #expect(throws: (any Error).self) { try await service.plan(versions: [version("a2", project: "a"), version("a3", project: "a")], kind: .mod, instance: instance) }
    }
}
