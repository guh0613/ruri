import Foundation
import Testing
@testable import RuriCore

@Suite struct RepositoryRunDirectoryCopyTests {
    private struct Fixture: Sendable {
        let root: URL
        let repository: URL
        let paths: LauncherPaths
        let instance: GameInstance
        let other: GameInstance
    }
    private func fixture(mode: GameRunDirectory) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-repository-copy-" + UUID().uuidString)
        let repository = root.appendingPathComponent("Minecraft"), base = LauncherPaths(root: root.appendingPathComponent("Ruri"))
        for name in ["Profile", "Other"] {
            let version = repository.appendingPathComponent("versions/" + name)
            try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
            try JSONEncoder().encode(VersionManifest(id: name, mainClass: "example.Main", libraries: [])).write(to: version.appendingPathComponent(name + ".json"))
        }
        var state = try MinecraftFolderStore.add(name: "Games", url: repository, paths: base)
        let index = state.instances.firstIndex { $0.repositoryVersionID == "Profile" }!
        state.instances[index].runDirectory = mode
        state = try StateStore.save(state, to: base)
        let instance = state.instances[index], paths = base.configured(with: state)
        let other = state.instances.first { $0.repositoryVersionID == "Other" }!
        for (name, contents) in ["versions/Profile/Profile.jar": "client", "libraries/required.jar": "library", "assets/index.json": "asset", "launcher_accounts.json": "account secret", "launcher_msa_credentials.bin": "credential", ".hmcl/settings.json": "launcher config"] {
            let file = repository.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: file)
        }
        return .init(root: root, repository: repository, paths: paths, instance: instance, other: other)
    }
    private func gameData(_ fixture: Fixture) async throws {
        try Data("game settings".utf8).write(to: fixture.paths.game(fixture.instance.id).appendingPathComponent("options.txt"))
        let mod = fixture.paths.cache.appendingPathComponent("fixture.jar")
        try Data("mod bytes".utf8).write(to: mod)
        let record = ManagedContent(projectID: "example", versionID: "old", title: "Example", versionName: "1", kind: .mod, filename: "example.jar", size: 9)
        try await ContentManager(paths: fixture.paths, instanceID: fixture.instance.id).install([.init(record: record, source: mod)])
        let world = fixture.paths.game(fixture.instance.id).appendingPathComponent("saves/World")
        try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
        try WorldTests().nbt().write(to: world.appendingPathComponent("level.dat"))
        _ = try await WorldManager(paths: fixture.paths, instanceID: fixture.instance.id).backup(folder: "World")
    }

    @Test(arguments: [GameRunDirectory.isolated, .shared])
    func copiesBetweenRepositoryAndVersionWithoutMovingInstallationFiles(mode: GameRunDirectory) async throws {
        let fixture = try await fixture(mode: mode); defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await gameData(fixture)
        let originalManifest = try Data(contentsOf: fixture.paths.manifest(fixture.instance.id))
        let originalBackup = try #require(try await WorldManager(paths: fixture.paths, instanceID: fixture.instance.id).backups().first)
        let backup = try Data(contentsOf: originalBackup.url)
        let service = GameRunDirectoryChange(paths: fixture.paths)
        let target: GameRunDirectory = mode == .isolated ? .shared : .isolated
        let preview = try await service.preview(instanceID: fixture.instance.id, target: target)
        #expect(preview.canCopyToTarget)
        #expect(!preview.sourceSnapshot.game.contains { $0.path.hasPrefix("libraries/") || $0.path.hasPrefix("assets/") || $0.path.hasPrefix("versions/") || $0.path.hasPrefix("launcher_") })
        let result = try await service.copyToEmpty(preview), current = fixture.paths.configured(with: result.state)
        #expect(result.state.instances.first { $0.id == fixture.instance.id }?.runDirectory == target)
        #expect(try String(contentsOf: current.game(fixture.instance.id).appendingPathComponent("options.txt"), encoding: .utf8) == "game settings")
        #expect(try Data(contentsOf: current.manifest(fixture.instance.id)) == originalManifest)
        #expect(try String(contentsOf: fixture.repository.appendingPathComponent("versions/Profile/Profile.jar"), encoding: .utf8) == "client")
        #expect(try String(contentsOf: fixture.repository.appendingPathComponent("launcher_accounts.json"), encoding: .utf8) == "account secret")
        #expect(try await ContentManager(paths: current, instanceID: fixture.instance.id).records().first?.projectID == "example")
        let copiedBackup = try #require(try await WorldManager(paths: current, instanceID: fixture.instance.id).backups().first)
        #expect(try Data(contentsOf: copiedBackup.url) == backup)
        try Data("changed copy".utf8).write(to: current.game(fixture.instance.id).appendingPathComponent("options.txt"))
        #expect(try String(contentsOf: fixture.paths.game(fixture.instance.id).appendingPathComponent("options.txt"), encoding: .utf8) == "game settings")
        #expect(!RunDirectoryCopyGuard.hasPending(paths: current, instanceID: fixture.instance.id))
    }

    @Test func copiesToCustomRootAndTreatsItsOwnLibrariesAsGameData() async throws {
        let fixture = try await fixture(mode: .isolated); defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await gameData(fixture)
        let custom = fixture.root.appendingPathComponent("Custom")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let location = try CustomRunDirectory.register(at: custom, paths: fixture.paths)
        let service = GameRunDirectoryChange(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.instance.id, target: .custom, customDirectory: location)
        let result = try await service.copyToEmpty(preview), current = fixture.paths.configured(with: result.state)
        #expect(current.game(fixture.instance.id).path == custom.path)
        #expect(FileManager.default.fileExists(atPath: custom.appendingPathComponent("saves/World/level.dat").path))
        try FileManager.default.createDirectory(at: custom.appendingPathComponent("libraries"), withIntermediateDirectories: true)
        try Data("custom gameplay data".utf8).write(to: custom.appendingPathComponent("libraries/keep.dat"))
        let snapshot = try RunDirectorySnapshot.read(paths: current, instanceID: fixture.instance.id)
        #expect(snapshot.game.contains { $0.path == "libraries/keep.dat" })
        let blocked = try await service.preview(instanceID: fixture.instance.id, target: .shared)
        #expect(!blocked.canCopyToTarget && blocked.copyIssue?.contains("libraries") == true)
        await #expect(throws: (any Error).self) { try await service.copyToEmpty(blocked) }
    }

    @Test func cancellationAfterPublicationKeepsSourceAndSharedRepositoryResources() async throws {
        let fixture = try await fixture(mode: .isolated); defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await gameData(fixture)
        let service = GameRunDirectoryChange(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.instance.id, target: .shared)
        let work = Task {
            try await service.copyToEmpty(preview) { value in
                if value.phase == .publishing && value.completed == 1 {
                    #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: fixture.paths, instanceID: fixture.other.id) }
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do { _ = try await work.value; Issue.record("Expected cancellation") }
        catch let failure as RunDirectoryCopyFailure { #expect(failure.cancelled && failure.preservedCopy != nil) }
        #expect(try StateStore.load(fixture.paths).instances.first { $0.id == fixture.instance.id }?.runDirectory == .isolated)
        #expect(FileManager.default.fileExists(atPath: fixture.paths.game(fixture.instance.id).appendingPathComponent("mods/example.jar").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.repository.appendingPathComponent("options.txt").path))
        #expect(try String(contentsOf: fixture.repository.appendingPathComponent("libraries/required.jar"), encoding: .utf8) == "library")
        #expect(!RunDirectoryCopyGuard.hasPending(paths: fixture.paths, instanceID: fixture.other.id))
    }

    @Test func nestedCustomDestinationCannotCopyTheSourceIntoItself() async throws {
        let fixture = try await fixture(mode: .isolated); defer { try? FileManager.default.removeItem(at: fixture.root) }
        try await gameData(fixture)
        let nested = fixture.paths.game(fixture.instance.id).appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let custom = try CustomRunDirectory.register(at: nested, paths: fixture.paths)
        let service = GameRunDirectoryChange(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.instance.id, target: .custom, customDirectory: custom)
        #expect(!preview.canCopyToTarget && preview.copyIssue?.contains("互相包含") == true)
        await #expect(throws: (any Error).self) { try await service.copyToEmpty(preview) }
    }
}
