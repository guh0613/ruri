import Foundation
import Testing
@testable import RuriCore

@Suite struct MinecraftFolderTests {
    private func fixture() throws -> (URL, LauncherPaths, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-folder-tests-" + UUID().uuidString)
        let repository = base.appendingPathComponent("Minecraft")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        return (base, LauncherPaths(root: base.appendingPathComponent("Ruri")), repository)
    }
    private func version(_ name: String, root: URL, extra: [String: Any] = [:]) throws -> URL {
        let directory = root.appendingPathComponent("versions/" + name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var raw: [String: Any] = ["id": name, "mainClass": "example.Main", "libraries": [], "minecraftArguments": "--username ${auth_player_name}"]
        raw.merge(extra) { _, new in new }
        try JSONSerialization.data(withJSONObject: raw).write(to: directory.appendingPathComponent(name + ".json"))
        return directory
    }
    @Test func attachesAllVersionsInPlaceAndPreservesSettingsOnRefresh() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let a = try version("1.21.1", root: root)
        try Data("{}".utf8).write(to: a.appendingPathComponent("modpack.cfg"))
        _ = try version("1.20.1", root: root)
        let original = try Data(contentsOf: a.appendingPathComponent("1.21.1.json"))
        var state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        #expect(state.instances.count == 2)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "1.21.1" })
        let configured = paths.configured(with: state)
        #expect(configured.game(instance.id).path == a.path)
        #expect(configured.manifest(instance.id) == a.appendingPathComponent("1.21.1.json"))
        #expect(try configured.resources(for: instance).root.path == root.path)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".ruri/instances").path))
        #expect(try Data(contentsOf: a.appendingPathComponent("1.21.1.json")) == original)
        state.instances[state.instances.firstIndex { $0.id == instance.id }!].favorite = true
        _ = try StateStore.save(state, to: paths)
        _ = try version("1.19.4", root: root)
        state = try MinecraftFolderStore.refresh(state.selectedDirectoryID!, paths: paths)
        #expect(state.instances.count == 3)
        #expect(state.instances.first { $0.id == instance.id }?.favorite == true)
        #expect(try MinecraftFolderStore.add(name: "Again", url: root, paths: paths).gameDirectories?.count == 1)
    }
    @Test func switchingFoldersSelectsTheirInstancesAndSupportsEmptyNewFolders() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let first = try MinecraftFolderStore.add(name: "A", url: root, paths: paths)
        let other = base.appendingPathComponent("B"); try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let second = try MinecraftFolderStore.add(name: "B", url: other, paths: paths)
        #expect(second.selectedInstanceID == nil)
        var input = GameInstance(name: "New Fabric", gameVersion: "1.21.1"); input.directoryID = second.selectedDirectoryID
        let new = try MinecraftFolderStore.preparingNewInstance(input, paths: paths.configured(with: second))
        let target = paths.configured(with: second).including(new)
        #expect(target.game(new.id) == other.appendingPathComponent("versions/New Fabric"))
        #expect(try target.resources(for: new).libraries == other.appendingPathComponent("libraries"))
        let switched = try GameDirectoryStore.select(first.selectedDirectoryID!, paths: paths)
        #expect(switched.selectedInstanceID == first.selectedInstanceID)
        input.name = "1.21.1"; input.directoryID = first.selectedDirectoryID
        #expect(throws: (any Error).self) { try MinecraftFolderStore.preparingNewInstance(input, paths: paths.configured(with: switched)) }
    }
    @Test func loadsFreshInheritedManifestAndLocalLibrariesWithoutCopying() async throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let child = try version("Fabric", root: root, extra: ["inheritsFrom": "1.21.1", "libraries": [["name": "example:helper:1", "hint": "local", "filename": "helper.jar"]]])
        let state = try MinecraftFolderStore.add(name: "Game", url: root, paths: paths)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "Fabric" })
        let configured = paths.configured(with: state), installer = GameInstaller(paths: paths.configured(with: state))
        let first = try await installer.loadManifest(instance)
        #expect(first.jar == "1.21.1")
        let artifact = try #require(try first.libraries.first?.artifact())
        #expect(try configured.resources(for: instance).libraryFile(artifact) == child.appendingPathComponent("libraries/helper.jar"))
        _ = try version("Fabric", root: root, extra: ["inheritsFrom": "1.21.1", "mainClass": "example.Updated"])
        #expect(try await installer.loadManifest(instance).mainClass == "example.Updated")
        #expect(!FileManager.default.fileExists(atPath: configured.instance(instance.id).path))
    }
    @Test func brokenAndRemovedVersionsStayVisibleWithoutBecomingNewInstallations() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let folder = try version("1.21.1", root: root)
        var state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("1.21.1.json"))
        state = try MinecraftFolderStore.refresh(state.selectedDirectoryID!, paths: paths)
        #expect(state.instances.first?.repositoryIssue != nil)
        #expect(state.instances.first?.installed == true)
        try FileManager.default.removeItem(at: folder)
        state = try MinecraftFolderStore.refresh(state.selectedDirectoryID!, paths: paths)
        #expect(state.instances.first?.repositoryIssue != nil)
        #expect(state.instances.count == 1)
    }
    @Test func isolationSwitchUsesExistingDataAndSkipsRepositoryResources() async throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let folder = try version("1.21.1", root: root)
        try Data("shared settings".utf8).write(to: root.appendingPathComponent("options.txt"))
        try Data("isolated settings".utf8).write(to: folder.appendingPathComponent("options.txt"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("modpack.cfg"))
        let state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let instance = try #require(state.instances.first)
        let service = GameRunDirectoryChange(paths: paths)
        let preview = try await service.preview(instanceID: instance.id, target: .shared)
        #expect(preview.sourceSnapshot.game.map(\.path) == ["options.txt"])
        #expect(preview.targetSnapshot.game.map(\.path) == ["options.txt"])
        let changed = try await service.useExisting(preview)
        #expect(paths.configured(with: changed).game(instance.id).path == root.path)
        #expect(try String(contentsOf: folder.appendingPathComponent("options.txt"), encoding: .utf8) == "isolated settings")
        let restored = try await service.preview(instanceID: instance.id, target: .isolated)
        #expect(try await service.useExisting(restored).instances.first?.runDirectory == .isolated)
    }

    @Test @MainActor func reattachmentRestoresPreferencesSelectionAndHistoryWhileDiscoveringChanges() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let folder = try version("1.21.1", root: root)
        var state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let id = try #require(state.selectedDirectoryID)
        state.instances[0].name = "My game"; state.instances[0].favorite = true
        state.instances[0].playTime = 120; state.instances[0].lastPlayed = Date()
        state.instances[0].launchOverrides?.jvmArguments = "-Dexample=true"
        state = try StateStore.save(state, to: paths)
        let instance = try #require(state.instances.first), current = paths.configured(with: state)
        let recorder = try GameSessionRecorder(paths: current, instance: instance, accountMode: "offline")
        try recorder.fail(RuriError.message("Retained history"), cancelled: false)
        let history = try GameSessionStore.logTail(paths: current, session: recorder.record)
        let source = try Data(contentsOf: folder.appendingPathComponent("1.21.1.json"))
        let removed = try GameDirectoryStore.remove(id, paths: paths)
        #expect(removed.instances.isEmpty && removed.selectedInstanceID == nil)
        #expect(removed.detachedMinecraftFolders?.first?.instances == [instance])
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: current, instanceID: instance.id) }
        #expect(throws: (any Error).self) { try current.prepareInstance(instance.id) }
        _ = try version("1.20.1", root: root)
        let restored = try MinecraftFolderStore.add(name: "Restored", url: root, paths: paths)
        #expect(restored.selectedDirectoryID == id && restored.selectedInstanceID == instance.id)
        #expect(restored.gameDirectories?.first?.createdAt == state.gameDirectories?.first?.createdAt)
        #expect(restored.instances.first { $0.id == instance.id } == instance)
        #expect(restored.instances.count == 2 && restored.detachedMinecraftFolders?.isEmpty == true)
        #expect(try GameSessionStore.logTail(paths: paths.configured(with: restored), session: recorder.record) == history)
        #expect(try Data(contentsOf: folder.appendingPathComponent("1.21.1.json")) == source)
        let lease = try GameRunLease.acquire(paths: paths.configured(with: restored), instanceID: instance.id)
        withExtendedLifetime(lease) {}
    }

    @Test func unregisteringRejectsRunningGamesAndOpenFileOperations() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let id = try #require(state.selectedDirectoryID), instance = try #require(state.instances.first)
        let current = paths.configured(with: state), original = try Data(contentsOf: paths.state)
        do {
            let lease = try GameRunLease.acquire(paths: current, instanceID: instance.id)
            #expect(throws: (any Error).self) { try GameDirectoryStore.remove(id, paths: paths) }
            withExtendedLifetime(lease) {}
        }
        do {
            let lease = try InstanceLocationLease.acquire(paths: current, instanceID: instance.id)
            #expect(throws: (any Error).self) { try GameDirectoryStore.remove(id, paths: paths) }
            withExtendedLifetime(lease) {}
        }
        #expect(try Data(contentsOf: paths.state) == original)
        #expect(try GameDirectoryStore.remove(id, paths: paths).detachedMinecraftFolders?.count == 1)
    }

    @Test func staleWritersCannotResurrectDetachedInstancesButUnrelatedPreferencesMerge() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let baseline = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        _ = try GameDirectoryStore.remove(baseline.selectedDirectoryID!, paths: paths)
        var local = baseline; local.instances[0].favorite = true
        #expect(throws: (any Error).self) { try StateStore.save(local, to: paths, basedOn: baseline) }
        local = baseline; local.settings.appearance = "dark"
        let merged = try StateStore.save(local, to: paths, basedOn: baseline)
        #expect(merged.instances.isEmpty && merged.detachedMinecraftFolders?.first?.instances == baseline.instances)
        #expect(merged.settings.appearance == "dark")
        _ = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        var detachedWriter = merged; detachedWriter.settings.concurrentDownloads = 3
        let reattached = try StateStore.save(detachedWriter, to: paths, basedOn: merged)
        #expect(reattached.instances == baseline.instances && reattached.detachedMinecraftFolders?.isEmpty == true)
        #expect(reattached.settings.concurrentDownloads == 3)
    }

    @Test func movedDetachedFolderRestoresIdentityAndMissingRowsWithoutClaimingAnAccessibleCopy() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let folder = try version("1.21.1", root: root)
        let state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        _ = try GameDirectoryStore.remove(state.selectedDirectoryID!, paths: paths)
        let before = try Data(contentsOf: paths.state)
        let copy = base.appendingPathComponent("Copied")
        try FileManager.default.copyItem(at: root, to: copy)
        #expect(throws: (any Error).self) { try MinecraftFolderStore.add(name: "Copy", url: copy, paths: paths) }
        #expect(try Data(contentsOf: paths.state) == before)
        try FileManager.default.removeItem(at: folder)
        let moved = base.appendingPathComponent("Renamed")
        try FileManager.default.moveItem(at: root, to: moved)
        let restored = try MinecraftFolderStore.add(name: "Moved", url: moved, paths: paths)
        #expect(restored.selectedDirectoryID == state.selectedDirectoryID)
        #expect(restored.instances.first?.id == state.instances.first?.id)
        #expect(restored.instances.first?.repositoryIssue != nil)
        #expect(restored.gameDirectories?.first?.url.path == moved.path)
    }

    @Test func invalidDetachedRecordsAreRejectedWithoutChangingState() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let active = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let detached = try GameDirectoryStore.remove(active.selectedDirectoryID!, paths: paths)
        let bytes = try Data(contentsOf: paths.state)
        var invalid = detached; invalid.instances = active.instances; invalid.gameDirectories = active.gameDirectories
        #expect(throws: (any Error).self) { try StateStore.save(invalid, to: paths) }
        invalid = detached; invalid.detachedMinecraftFolders?[0].instances[0].directoryID = UUID()
        #expect(throws: (any Error).self) { try StateStore.save(invalid, to: paths) }
        invalid = detached; invalid.detachedMinecraftFolders?[0].selectedInstanceID = UUID()
        #expect(throws: (any Error).self) { try StateStore.save(invalid, to: paths) }
        #expect(try Data(contentsOf: paths.state) == bytes)
    }

    @Test func explicitRestoreRequiresTheOriginalMarkerAndKeepsItsDisplayName() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        let state = try MinecraftFolderStore.add(name: "My collection", url: root, paths: paths)
        let id = try #require(state.selectedDirectoryID)
        _ = try GameDirectoryStore.remove(id, paths: paths)
        let wrong = base.appendingPathComponent("Different")
        try FileManager.default.createDirectory(at: wrong, withIntermediateDirectories: true)
        _ = try version("1.21.1", root: wrong)
        let bytes = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) { try MinecraftFolderStore.restore(id, from: wrong, paths: paths) }
        #expect(try Data(contentsOf: paths.state) == bytes)
        #expect(!FileManager.default.fileExists(atPath: wrong.appendingPathComponent(GameDirectory.markerName).path))
        let restored = try MinecraftFolderStore.restore(id, from: root, paths: paths)
        #expect(restored.gameDirectories?.first?.name == "My collection")
        #expect(restored.instances == state.instances)
        #expect(throws: (any Error).self) { try MinecraftFolderStore.restore(id, from: root, paths: paths) }
        #expect(try StateStore.load(paths) == restored)
    }

    @Test func reattachingDoesNotReplaceUnavailableCustomGameDataWithSharedData() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        _ = try version("1.21.1", root: root)
        var state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let custom = base.appendingPathComponent("Custom")
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        state.instances[0].runDirectory = .custom
        state.instances[0].customRunDirectory = try CustomRunDirectory.register(at: custom, paths: paths.configured(with: state))
        state = try StateStore.save(state, to: paths)
        _ = try GameDirectoryStore.remove(state.selectedDirectoryID!, paths: paths)
        try FileManager.default.moveItem(at: custom, to: base.appendingPathComponent("Offline"))
        let restored = try MinecraftFolderStore.restore(state.selectedDirectoryID!, from: root, paths: paths)
        #expect(restored.instances == state.instances)
        let current = paths.configured(with: restored), instance = try #require(restored.instances.first)
        #expect(current.game(instance.id).path == custom.path)
        #expect(throws: (any Error).self) { try current.validateInstanceLocation(instance.id) }
        #expect(!FileManager.default.fileExists(atPath: custom.path))
    }

    @Test func parentDeletionIsBlockedAndRemovingFolderKeepsAllVersions() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let parent = try version("1.21.1", root: root)
        _ = try version("Fabric", root: root, extra: ["inheritsFrom": "1.21.1"])
        let state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "1.21.1" })
        #expect(throws: (any Error).self) { try MinecraftFolderStore.trashVersion(instance.id, paths: paths) }
        #expect(FileManager.default.fileExists(atPath: parent.appendingPathComponent("1.21.1.json").path))
        let removed = try GameDirectoryStore.remove(state.selectedDirectoryID!, paths: paths)
        #expect(removed.instances.isEmpty && removed.gameDirectories?.isEmpty == true)
        #expect(FileManager.default.fileExists(atPath: parent.appendingPathComponent("1.21.1.json").path))
        #expect(try MinecraftFolderStore.add(name: "Games again", url: root, paths: paths).instances.count == 2)
    }

    @Test func loggingWithoutFileIDSupportsLaunchAndDependencyChecks() async throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let parent = try version("1.21.1", root: root, extra: ["logging": ["client": [
            "argument": "-Dlog4j.configurationFile=${path}",
            "file": ["url": "https://fixture.invalid/objects/hash/client-1.12.xml", "sha1": "hash", "size": 888]
        ]]])
        try Data("fixture jar".utf8).write(to: parent.appendingPathComponent("1.21.1.jar"))
        _ = try version("Fabric", root: root, extra: ["inheritsFrom": "1.21.1"])
        let source = try Data(contentsOf: parent.appendingPathComponent("1.21.1.json"))
        let state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "1.21.1" })
        let current = paths.configured(with: state)
        let manifest = try await GameInstaller(paths: current).loadManifest(instance)
        let java = JavaRuntime(path: "/fixture/java", version: "21", major: 21,
                               architecture: GameInstaller.architecture(for: manifest), vendor: "Fixture")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java,
                                          account: Account(username: "Player"), paths: current)
        #expect(plan.arguments.contains("-Dlog4j.configurationFile=\(root.appendingPathComponent("assets/log_configs/client-1.12.xml").path)"))
        #expect(manifest.logging?.client?.file.sha1 == "hash")
        #expect(manifest.logging?.client?.file.size == 888)
        // Deletion must reach the dependency check, not fail decoding a
        // different version's inherited logging configuration.
        do {
            _ = try MinecraftFolderStore.trashVersion(instance.id, paths: paths)
            Issue.record("Expected dependent version to prevent deletion")
        } catch {
            #expect(error is RuriError)
            #expect(error.localizedDescription.contains("Fabric"))
        }
        #expect(try Data(contentsOf: parent.appendingPathComponent("1.21.1.json")) == source)
    }

    @Test func deletesIndependentVersionWhenOtherVersionsOmitLoggingFileID() throws {
        let (base, paths, root) = try fixture(); defer { try? FileManager.default.removeItem(at: base) }
        let extra: [String: Any] = ["logging": ["client": ["argument": "-Dlog4j.configurationFile=${path}",
                                                          "file": ["url": "https://fixture.invalid/client.xml"]]]]
        let target = try version("Snapshot", root: root, extra: extra)
        let other = try version("1.21.1", root: root, extra: extra)
        let shared = root.appendingPathComponent("options.txt")
        try Data("shared game data".utf8).write(to: shared)
        let state = try MinecraftFolderStore.add(name: "Games", url: root, paths: paths)
        let instance = try #require(state.instances.first { $0.repositoryVersionID == "Snapshot" })
        let trash = base.appendingPathComponent("Trash")
        let remaining = try MinecraftFolderStore.trashVersion(instance.id, paths: paths) { folder in
            #expect(folder.path == target.path)
            try FileManager.default.moveItem(at: folder, to: trash)
        }
        #expect(!remaining.instances.contains { $0.id == instance.id })
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Snapshot.json").path))
        #expect(FileManager.default.fileExists(atPath: other.appendingPathComponent("1.21.1.json").path))
        #expect(try String(contentsOf: shared, encoding: .utf8) == "shared game data")
        #expect(try StateStore.load(paths).instances == remaining.instances)
    }

}
