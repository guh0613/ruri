import Foundation
import Testing
@testable import RuriCore

struct ModpackUpdateTests {
    private func write(_ text: String, to path: String, in root: URL) throws {
        let file = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    private func fixture(repository: Bool = false) throws -> (LauncherPaths, GameInstance, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-pack-update-\(UUID())")
        let paths = LauncherPaths(root: root.appendingPathComponent("Ruri")); try paths.prepare()
        var original = GameInstance(name: "Personal", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.1")
        original.installed = true; original.playTime = 120
        if repository {
            let repository = root.appendingPathComponent("Minecraft")
            try write(#"{"id":"Pack","clientVersion":"1.21.1","mainClass":"OldMain","libraries":[],"patches":[{"id":"fabric","version":"0.1"}]}"#, to: "versions/Pack/Pack.json", in: repository)
            let added = try MinecraftFolderStore.add(name: "Minecraft", url: repository, paths: paths)
            original = try #require(added.instances.first); original.runDirectory = .isolated; original.name = "Personal"; original.playTime = 120
        }
        var state = try StateStore.load(paths); state.instances = [original]; try StateStore.save(state, to: paths)
        let configured = paths.configured(with: state); try configured.prepareInstance(original.id)
        if !repository { try write(#"{"id":"1.21.1","mainClass":"OldMain","libraries":[]}"#, to: "version.json", in: configured.instance(original.id)) }
        let client = try configured.clientJar(original.repositoryVersionID ?? original.gameVersion, instance: original)
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("old client".utf8).write(to: client)
        let game = configured.game(original.id)
        let originals = ["mods/old.jar": "old mod", "config/local.txt": "old default", "config/normal.txt": "old default", "config/removed.txt": "removed default", "saves/World/region/data": "world data"]
        var files: [InstalledModpack.File] = []
        for (path, text) in originals {
            try write(text, to: path, in: game)
            files.append(.init(path: path, sha1: try InstanceTransfer.sha1(game.appendingPathComponent(path)), size: Int64(text.utf8.count), force: false, identities: path == "mods/old.jar" ? ["modrinth:project"] : []))
        }
        let record = InstalledModpack(format: "Modrinth", name: "Fixture", version: "v1", origin: .init(provider: .modrinth, projectID: "pack", versionID: "old"), settings: original, files: files)
        try ModpackRegistry.save(record, paths: configured, instanceID: original.id)
        try FileManager.default.moveItem(at: game.appendingPathComponent("mods/old.jar"), to: game.appendingPathComponent("mods/old.jar.disabled"))
        try write("personal setting", to: "config/local.txt", in: game)
        try write("personal mod", to: "mods/personal.jar", in: game)
        let source = root.appendingPathComponent("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let index = ModpackIndex(formatVersion: 1, game: "minecraft", name: "Fixture", versionId: "v2", dependencies: ["minecraft": "1.21.2", "fabric-loader": "0.19.5"], files: [MRPackTests().file("mods/new.jar")])
        try JSONEncoder().encode(index).write(to: source.appendingPathComponent("modrinth.index.json"))
        try write("new default", to: "overrides/config/local.txt", in: source)
        try write("new default", to: "overrides/config/normal.txt", in: source)
        try write("replacement world", to: "overrides/saves/World/region/data", in: source)
        return (configured, original, source)
    }
    private static func install(_ candidate: GameInstance, paths: LauncherPaths) throws -> GameInstance {
        let client = try paths.clientJar(candidate.gameVersion, instance: candidate)
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("new client".utf8).write(to: client)
        let manifest = VersionManifest(id: candidate.gameVersion, mainClass: "NewMain", libraries: [])
        try JSONEncoder().encode(manifest).write(to: paths.manifest(candidate.id))
        var installed = candidate; installed.installed = true; return installed
    }
    @Test(arguments: [false, true]) func updatesRuntimeAndPackFilesThenRollsBackWithoutReplacingUserChanges(_ repository: Bool) async throws {
        let (paths, original, source) = try fixture(repository: repository)
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let transfer = InstanceTransfer(paths: paths), service = ModpackUpdater(paths: paths, downloader: DownloadManager(configuration: MRPackTests().config(), retryDelay: .zero))
        let prepared = try await transfer.prepare(source, origin: .init(provider: .modrinth, projectID: "pack", versionID: "new"))
        let oldJSON = try Data(contentsOf: paths.manifest(original.id))
        let plan = try await service.prepare(prepared, for: original)
        let local = try #require(plan.changes.first { $0.id == "config/local.txt" })
        #expect(local.conflict && local.action == .keep)
        #expect(plan.changes.first { $0.id == "mods/new.jar" }?.targetPath == "mods/new.jar.disabled")
        let kept = Set(plan.changes.filter { $0.action == .keep }.map(\.id))
        let saved = try await service.apply(plan, keepingLocal: kept, installing: { candidate, staging in
            try StateStore.update(paths) { $0.instances[0].memoryMB = 6144 }
            return try Self.install(candidate, paths: staging)
        })
        let instance = try #require(saved.instances.first), game = paths.game(instance.id)
        #expect(instance.id == original.id && instance.gameVersion == "1.21.2" && instance.memoryMB == 6144 && instance.playTime == 120)
        #expect(FileManager.default.fileExists(atPath: game.appendingPathComponent("mods/new.jar.disabled").path))
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("mods/old.jar.disabled").path))
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("config/removed.txt").path))
        #expect(try String(contentsOf: game.appendingPathComponent("config/local.txt"), encoding: .utf8) == "personal setting")
        #expect(try String(contentsOf: game.appendingPathComponent("saves/World/region/data"), encoding: .utf8) == "world data")
        #expect(try ModpackRegistry.load(paths: paths, instanceID: instance.id)?.origin?.versionID == "new")
        let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
        #expect(manifest.mainClass == "NewMain")
        if let directory = instance.directoryID { #expect(try MinecraftFolderStore.refresh(directory, paths: paths).instances.first?.gameVersion == "1.21.2") }
        try write("edited after update", to: "config/normal.txt", in: game)
        try StateStore.update(paths) { $0.instances[0].memoryMB = 8192; $0.instances[0].name = "New personal name" }
        let restored = try await service.rollback(instance)
        #expect(restored.state.instances[0].gameVersion == "1.21.1" && restored.state.instances[0].memoryMB == 8192)
        #expect(restored.state.instances[0].name == "New personal name" && restored.preservedFiles == 1)
        #expect(try Data(contentsOf: paths.manifest(instance.id)) == oldJSON)
        #expect(try String(contentsOf: game.appendingPathComponent("config/normal.txt"), encoding: .utf8) == "edited after update")
        #expect(FileManager.default.fileExists(atPath: game.appendingPathComponent("mods/old.jar.disabled").path))
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("mods/new.jar.disabled").path))
        #expect(FileManager.default.fileExists(atPath: game.appendingPathComponent("mods/personal.jar").path))
        await transfer.discard(prepared)
    }
    @Test func changedFileAfterPreviewIsRejectedBeforeInstallation() async throws {
        let (paths, instance, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let prepared = try await InstanceTransfer(paths: paths).prepare(source)
        let service = ModpackUpdater(paths: paths, downloader: DownloadManager(configuration: MRPackTests().config(), retryDelay: .zero))
        let plan = try await service.prepare(prepared, for: instance)
        try write("changed after preview", to: "config/normal.txt", in: paths.game(instance.id))
        await #expect(throws: (any Error).self) {
            try await service.apply(plan, keepingLocal: [], installing: { _, _ in Issue.record("Installation must not begin with a stale preview"); throw CancellationError() })
        }
        #expect(try StateStore.load(paths).instances[0].gameVersion == "1.21.1")
        await service.discard(plan)
    }
    @Test func interruptedUpdateBlocksLaunchAndRecoversItsOriginalFiles() throws {
        let (base, source, _) = try fixture()
        var instance = source; instance.runDirectory = .shared
        var sibling = GameInstance(name: "Shared", gameVersion: "1.21.1"); sibling.runDirectory = .shared
        let state = try StateStore.update(base) { $0.instances = [instance, sibling] }
        let paths = base.configured(with: state)
        defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        try write("old default", to: "config/normal.txt", in: paths.game(instance.id))
        let directory = ModpackUpdateStore.pending(instance.id, paths: paths)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("files"), withIntermediateDirectories: true)
        let file = paths.game(instance.id).appendingPathComponent("config/normal.txt")
        let before = try #require(try ModpackUpdatePlanner.digest(file))
        try FileManager.default.copyItem(at: file, to: directory.appendingPathComponent("files/0"))
        try write("partially updated", to: "config/normal.txt", in: paths.game(instance.id))
        var updated = instance; updated.gameVersion = "1.21.2"; updated.lastModpackUpdateID = UUID()
        let journal = ModpackUpdateJournal(id: updated.lastModpackUpdateID!, original: instance, updated: updated,
            files: [.init(target: .init(scope: .game, path: "config/normal.txt"), group: "config", before: before, after: try ModpackUpdatePlanner.digest(file))])
        try JSONEncoder().encode(journal).write(to: directory.appendingPathComponent("journal.json"))
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: sibling.id) }
        _ = try ModpackUpdateStore.recover(instanceID: instance.id, paths: paths)
        #expect(try String(contentsOf: file, encoding: .utf8) == "old default")
        #expect(!ModpackUpdateStore.hasPending(paths: paths, instanceID: instance.id))
        let lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id); withExtendedLifetime(lease) {}
    }
}
