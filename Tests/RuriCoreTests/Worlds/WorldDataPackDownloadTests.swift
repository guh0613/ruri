import Foundation
import Testing
@testable import RuriCore

struct WorldDataPackDownloadTests {
    private func pack(_ name: String, in root: URL) throws -> URL {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"pack":{"description":"Example","pack_format":48}}"#.utf8).write(to: folder.appendingPathComponent("pack.mcmeta"))
        return folder
    }
    @Test func priorityPreservesBuiltinsAndBatchImportRejectsConflictsBeforeWriting() async throws {
        let (paths, _, manager, world) = try WorldTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let a = try pack("A", in: paths.cache), b = try pack("B", in: paths.cache)
        try await manager.importDataPacks(from: [a, b], folder: "World")
        let level = world.appendingPathComponent("level.dat")
        let original = try NBTReader.updatingDataPacks(Data(contentsOf: level), enabled: ["vanilla", "file/A", "mod:example", "file/B", "file/missing.zip"], disabled: ["file/disabled.zip"])
        try original.write(to: level)
        let before = try await manager.dataPackPriority(folder: "World")
        #expect(before.keys == ["file/missing.zip", "file/B", "mod:example", "file/A", "vanilla"])
        let newKeys = ["file/B", "file/missing.zip", "file/A", "mod:example", "vanilla"]
        try await manager.setDataPackPriority(newKeys, folder: "World", expecting: before)
        #expect(try Data(contentsOf: await manager.dataPackBackup(folder: "World")) == original)
        var reader = try NBTReader(data: Data(contentsOf: level))
        let config = try reader.read()["Data"]?["DataPacks"]
        #expect(config?["Enabled"] == .list(newKeys.reversed().map(NBTValue.string)))
        #expect(config?["Disabled"] == .list([.string("file/disabled.zip")]))
        let reordered = try Data(contentsOf: level)
        await #expect(throws: (any Error).self) { try await manager.setDataPackPriority(before.keys, folder: "World", expecting: before) }
        #expect(try Data(contentsOf: level) == reordered)
        let c = try pack("C", in: paths.cache)
        await #expect(throws: (any Error).self) { try await manager.importDataPacks(from: [c, a], folder: "World") }
        #expect(!FileManager.default.fileExists(atPath: world.appendingPathComponent("datapacks/C").path))
        #expect(try Data(contentsOf: level) == reordered)
        let current = try await manager.dataPackPriority(folder: "World")
        await #expect(throws: (any Error).self) { try await manager.setDataPackPriority(Array(current.keys.reversed()), folder: "World", expecting: current) }
        #expect(try Data(contentsOf: world.appendingPathComponent("region/r.0.0.mca")) == Data("generation-a".utf8))
    }

    @Test func onlinePlanSelectsDataPackArchivesAndInstallsRequiredDependencies() async throws {
        let (paths, id, manager, world) = try WorldTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Online data packs", gameVersion: "1.21.1"); instance.id = id; instance.installed = true
        var state = try StateStore.load(paths); state.instances = [instance]; try StateStore.save(state, to: paths)
        let source = try pack("archive-content", in: paths.cache), archive = paths.cache.appendingPathComponent("pack.zip")
        try SafeArchive.create(from: source, to: archive)
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize!, hash = try InstanceTransfer.sha1(archive)
        func version(_ id: String, project: String, required: String? = nil) -> [String: Any] {
            ["id": id, "project_id": project, "name": project, "version_number": "1.0", "version_type": "release",
             "game_versions": ["1.21.1"], "loaders": ["datapack"],
             "files": [["url": "https://files.test/\(id).jar", "filename": id + ".jar", "size": size, "primary": true, "hashes": ["sha1": hash]],
                       ["url": "https://files.test/\(id).zip", "filename": id + ".zip", "size": size, "primary": false, "hashes": ["sha1": hash]]],
             "dependencies": required.map { [["project_id": $0, "dependency_type": "required"]] } ?? []]
        }
        let root = version("root", project: "main", required: "dependency"), dependency = version("dep", project: "dependency")
        let fixture = EndpointHTTPFixture([
            "api.modrinth.com/v2/project/main/version": try JSONSerialization.data(withJSONObject: [root]),
            "api.modrinth.com/v2/project/dependency/version": try JSONSerialization.data(withJSONObject: [dependency]),
            "api.modrinth.com/v2/search": Data(#"{"hits":[],"total_hits":0}"#.utf8)
        ])
        defer { fixture.close() }
        let service = WorldDataPackDownloads(client: HTTPClient(session: fixture.session))
        _ = try await service.search("example", game: "1.21.1")
        let versions = try await service.versions(project: "main", game: "1.21.1")
        let selected = try #require(versions.first), plan = try await service.prepare(selected, game: "1.21.1")
        #expect(plan.files.map(\.filename) == ["root.zip", "dep.zip"])
        for (version, file) in zip(plan.versions, plan.files) {
            let target = paths.cache.appendingPathComponent("datapacks/\(version.id)/\(file.filename)")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: archive, to: target)
        }
        try await service.install(plan, instance: instance, folder: "World", paths: paths, downloader: DownloadManager()) { _ in }
        #expect(try await manager.dataPacks(folder: "World").map(\.id) == ["dep.zip", "root.zip"])
        #expect(try await manager.dataPacks(folder: "World").allSatisfy(\.enabled))
        #expect(try await manager.dataPackPriority(folder: "World").keys == ["file/root.zip", "file/dep.zip", "vanilla"])
        #expect(try Data(contentsOf: world.appendingPathComponent("datapacks/root.zip")) == Data(contentsOf: archive))
        let query = try #require(fixture.requests.first.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "facets" }?.value })
        #expect(query.contains("project_type:datapack") && query.contains("versions:1.21.1"))
        await #expect(throws: (any Error).self) { try await service.prepare(selected, game: "1.20.1") }
        let saved = try Data(contentsOf: world.appendingPathComponent("level.dat"))
        await #expect(throws: (any Error).self) { try await service.install(plan, instance: instance, folder: "World", paths: paths, downloader: DownloadManager()) { _ in } }
        #expect(try Data(contentsOf: world.appendingPathComponent("level.dat")) == saved)
    }
}
