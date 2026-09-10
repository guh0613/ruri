import Foundation
import Testing
@testable import RuriCore

@Suite struct RepositoryInstanceCopyTests {
    private struct Fixture {
        let root: URL
        let paths: LauncherPaths
        let source: GameInstance
        let sourceDirectory: UUID
        let targetDirectory: UUID
        let target: URL
    }
    private func write(_ data: Data, _ relative: String, at root: URL) throws {
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }
    private func fixture(mode: GameRunDirectory = .isolated) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-repository-copy-" + UUID().uuidString)
        let repository = root.appendingPathComponent("Minecraft"), target = root.appendingPathComponent("Target")
        let base = LauncherPaths(root: root.appendingPathComponent("Ruri"))
        let library: [String: Any] = ["name": "example:common:1", "downloads": ["artifact": ["path": "example/common/1/common-1.jar", "sha1": String(repeating: "0", count: 40), "url": "https://example.invalid/common.jar"]]]
        let parent: [String: Any] = ["id": "1.21.1", "mainClass": "net.minecraft.client.main.Main", "libraries": [library],
                                     "downloads": ["client": ["sha1": String(repeating: "0", count: 40)]],
                                     "assetIndex": ["id": "test", "url": "https://example.invalid/index.json"]]
        let child: [String: Any] = ["id": "Original", "inheritsFrom": "1.21.1", "patches": [["id": "liteloader", "version": "fixture"]], "libraries": [["name": "example:local:1", "hint": "local", "filename": "custom.jar"]],
                                    "arguments": ["jvm": ["-Dlocal=" + repository.appendingPathComponent("versions/Original/libraries/custom.jar").path], "game": ["--username", "${auth_player_name}"]]]
        try write(JSONSerialization.data(withJSONObject: parent), "versions/1.21.1/1.21.1.json", at: repository)
        try write(JSONSerialization.data(withJSONObject: child), "versions/Original/Original.json", at: repository)
        try write(Data("locally modified client".utf8), "versions/1.21.1/1.21.1.jar", at: repository)
        try write(Data("locally modified common".utf8), "libraries/example/common/1/common-1.jar", at: repository)
        try write(Data("custom dependency".utf8), "versions/Original/libraries/custom.jar", at: repository)
        try write(Data("unrelated".utf8), "libraries/unrelated.jar", at: repository)
        let asset = Data("changed asset".utf8), oldHash = String(repeating: "a", count: 40)
        try write(asset, "assets/objects/aa/" + oldHash, at: repository)
        try write(JSONSerialization.data(withJSONObject: ["objects": ["example/sound.ogg": ["hash": oldHash, "size": 1]]]), "assets/indexes/test.json", at: repository)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let added = try MinecraftFolderStore.add(name: "Source", url: repository, paths: base)
        let sourceDirectory = try #require(added.selectedDirectoryID)
        let source = try #require(added.instances.first { $0.repositoryVersionID == "Original" })
        let targetState = try MinecraftFolderStore.add(name: "Target", url: target, paths: base)
        let targetDirectory = try #require(targetState.selectedDirectoryID)
        let state = try StateStore.update(base) { state in
            let index = state.instances.firstIndex { $0.id == source.id }!
            state.instances[index].runDirectory = mode
            state.instances[index].playTime = 120; state.instances[index].lastPlayed = Date(); state.instances[index].favorite = true
            state.instances[index].extraJVMArguments = "-Dcopy=preserved"
        }
        let current = base.configured(with: state), original = try #require(state.instances.first { $0.id == source.id })
        try current.prepareInstance(original.id)
        try write(Data("configuration".utf8), "config/example.txt", at: current.game(original.id))
        try write(Data("world bytes".utf8), "saves/World/data.dat", at: current.game(original.id))
        try write(Data("old log".utf8), "logs/latest.log", at: current.game(original.id))
        try write(Data("backup".utf8), "world-backups/fixture.zip", at: current.gameDataState(original.id))
        let pack = InstalledModpack(format: "MCBBS", name: "Local pack", version: "1", origin: nil, settings: original, files: [])
        try ModpackRegistry.save(pack, paths: current, instanceID: original.id)
        return .init(root: root, paths: current, source: original, sourceDirectory: sourceDirectory, targetDirectory: targetDirectory, target: target)
    }

    @Test(arguments: [GameRunDirectory.isolated, .shared])
    func copiesInheritedInstallationAndLocalBytesIntoIndependentVersion(mode: GameRunDirectory) async throws {
        let f = try fixture(mode: mode); defer { try? FileManager.default.removeItem(at: f.root) }
        let service = InstanceCopier(paths: f.paths)
        let preview = try await service.preview(instanceID: f.source.id, name: "My Copy", directoryID: f.targetDirectory,
                                                options: .init(includeWorlds: false, includeBackups: true))
        let result = try await service.copy(preview), current = f.paths.configured(with: result.state)
        let copy = try #require(result.state.instances.first { $0.id == preview.copy.id })
        #expect(copy.repositoryVersionID == "My Copy" && copy.runDirectory == .isolated && copy.importedInstallation == nil)
        #expect(copy.playTime == 0 && copy.lastPlayed == nil && !copy.favorite && copy.extraJVMArguments == "-Dcopy=preserved")
        #expect(current.game(copy.id) == f.target.appendingPathComponent("versions/My Copy"))
        #expect(try String(contentsOf: current.game(copy.id).appendingPathComponent("config/example.txt"), encoding: .utf8) == "configuration")
        #expect(!FileManager.default.fileExists(atPath: current.game(copy.id).appendingPathComponent("saves").path))
        #expect(!FileManager.default.fileExists(atPath: current.game(copy.id).appendingPathComponent("logs").path))
        #expect(FileManager.default.fileExists(atPath: current.gameDataState(copy.id).appendingPathComponent("world-backups/fixture.zip").path))
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(contentsOf: current.manifest(copy.id)))
        #expect(manifest.inheritsFrom == nil && manifest.jar == "My Copy" && manifest.id == "My Copy")
        let client = try current.clientJar("My Copy", instance: copy)
        #expect(try String(contentsOf: client, encoding: .utf8) == "locally modified client")
        #expect(manifest.downloads?["client"]?.sha1 == MinecraftInstallationCopy.sha1(Data("locally modified client".utf8)))
        let local = try #require(try manifest.libraries.first { $0.name == "example:local:1" }?.artifact())
        let localFile = try current.resources(for: copy).libraryFile(local)
        #expect(local.repositoryPath == nil && localFile.path.hasPrefix(f.target.path + "/libraries/ruri-local/"))
        #expect(try String(contentsOf: localFile, encoding: .utf8) == "custom dependency")
        #expect(manifest.arguments?.jvm?.contains(where: { if case .text(let value) = $0 { return value == "-Dlocal=" + localFile.path }; return false }) == true)
        #expect(!FileManager.default.fileExists(atPath: f.target.appendingPathComponent("libraries/unrelated.jar").path))
        let index = try #require(manifest.assetIndex)
        let objects = try JSONDecoder().decode(AssetObjects.self, from: Data(contentsOf: f.target.appendingPathComponent("assets/indexes/" + index.id + ".json")))
        let object = try #require(objects.objects["example/sound.ogg"])
        #expect(object.hash == MinecraftInstallationCopy.sha1(Data("changed asset".utf8)) && object.size == 13)
        #expect(FileManager.default.fileExists(atPath: f.target.appendingPathComponent("assets/objects/" + object.hash.prefix(2) + "/" + object.hash).path))
        let pack = try #require(try ModpackRegistry.load(paths: current, instanceID: copy.id))
        #expect(pack.settings.id == copy.id && pack.settings.repositoryVersionID == "My Copy" && pack.name == "Local pack")
        try Data("copy only".utf8).write(to: client)
        #expect(try String(contentsOf: f.root.appendingPathComponent("Minecraft/versions/1.21.1/1.21.1.jar"), encoding: .utf8) == "locally modified client")
        #expect(try RepositoryImportStore.pending(directoryID: f.targetDirectory, paths: f.paths).isEmpty)
        let refreshed = try MinecraftFolderStore.refresh(f.targetDirectory, paths: f.paths).instances.filter { $0.directoryID == f.targetDirectory }
        #expect(refreshed.map(\.id) == [copy.id])
        #expect(refreshed.first?.gameVersion == "1.21.1" && refreshed.first?.repositoryComponents == f.source.repositoryComponents)
    }

    @Test func sameRepositoryReusesResourcesAndStaleInputsOrCollisionsDoNotPublish() async throws {
        let f = try fixture(mode: .shared); defer { try? FileManager.default.removeItem(at: f.root) }
        let service = InstanceCopier(paths: f.paths)
        let preview = try await service.preview(instanceID: f.source.id, name: "Sibling", directoryID: f.sourceDirectory)
        let result = try await service.copy(preview), current = f.paths.configured(with: result.state)
        #expect(FileManager.default.fileExists(atPath: current.game(preview.copy.id).appendingPathComponent("saves/World/data.dat").path))
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: f.source.id, name: "Sibling", directoryID: f.sourceDirectory) }
        let stale = try await service.preview(instanceID: f.source.id, name: "Stale", directoryID: f.targetDirectory)
        try write(Data("different config".utf8), "config/example.txt", at: f.paths.game(f.source.id))
        await #expect(throws: (any Error).self) { try await service.copy(stale) }
        #expect(!FileManager.default.fileExists(atPath: stale.destination.path))
        let collision = try await service.preview(instanceID: f.source.id, name: "Collision", directoryID: f.targetDirectory)
        try write(Data("other installation".utf8), "libraries/example/common/1/common-1.jar", at: f.target)
        await #expect(throws: RunDirectoryCopyFailure.self) { try await service.copy(collision) }
        #expect(try String(contentsOf: f.target.appendingPathComponent("libraries/example/common/1/common-1.jar"), encoding: .utf8) == "other installation")
        #expect(!FileManager.default.fileExists(atPath: collision.destination.path))
        #expect(try RepositoryImportStore.pending(directoryID: f.targetDirectory, paths: f.paths).isEmpty)
    }

    @Test func managedInstallationCanBeCopiedIntoMinecraftFolder() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        var source = GameInstance(name: "Managed", gameVersion: "1.20.1"); source.installed = true
        let state = try StateStore.update(f.paths) { $0.instances.append(source) }, current = f.paths.configured(with: state)
        try current.prepareInstance(source.id)
        try write(JSONEncoder().encode(VersionManifest(id: "1.20.1", mainClass: "example.Main", libraries: [])), "version.json", at: current.instance(source.id))
        try write(Data("managed client".utf8), "versions/1.20.1/1.20.1.jar", at: current.root)
        let service = InstanceCopier(paths: current)
        let preview = try await service.preview(instanceID: source.id, name: "Managed Copy", directoryID: f.targetDirectory)
        let result = try await service.copy(preview)
        #expect(result.state.instances.contains { $0.id == preview.copy.id && $0.repositoryVersionID == "Managed Copy" })
        #expect(try String(contentsOf: preview.destination.appendingPathComponent("Managed Copy.jar"), encoding: .utf8) == "managed client")
    }

    @Test func copyRecoveryIsAvailableFromSourceAndTargetWithoutChangingOriginal() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let service = InstanceCopier(paths: f.paths)
        let preview = try await service.preview(instanceID: f.source.id, name: "Interrupted", directoryID: f.targetDirectory)
        let owner = InstanceCopyOwner(transactionID: preview.id, sourceID: f.source.id, copyID: preview.copy.id, sourceName: f.source.name, copyName: preview.copy.name)
        var transaction: RepositoryImportTransaction? = try .init(instance: preview.copy, paths: f.paths, copySource: owner)
        try write(Data("work in progress".utf8), "config/example.txt", at: transaction!.staging.game(preview.copy.id))
        #expect(try await service.pending(instanceID: f.source.id)?.owner == owner)
        #expect(try RepositoryImportStore.pending(directoryID: f.targetDirectory, paths: f.paths).first?.copySource == owner)
        withExtendedLifetime(transaction) {}; transaction = nil
        let result = try await service.recover(sourceID: f.source.id, transactionID: preview.id)
        let kept = try #require(result.preservedCopy)
        #expect(FileManager.default.fileExists(atPath: kept.appendingPathComponent("version/config/example.txt").path))
        #expect(result.state.instances.first { $0.id == f.source.id } == f.source)
        #expect(try await service.pending(instanceID: f.source.id) == nil)
    }
}
