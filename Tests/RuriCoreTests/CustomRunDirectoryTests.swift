import Foundation
import Testing
@testable import RuriCore

struct CustomRunDirectoryTests {
    private func fixture() throws -> (LauncherPaths, GameInstance, GameInstance, CustomRunDirectory) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-custom-\(UUID())")
        let base = LauncherPaths(root: root.appendingPathComponent("data"))
        let game = root.appendingPathComponent("My game 中文"), collection = root.appendingPathComponent("Other collection")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: collection, withIntermediateDirectories: true)
        try Data("original-options".utf8).write(to: game.appendingPathComponent("options.txt"))
        let custom = try CustomRunDirectory.register(at: game, paths: base)
        let folder = try GameDirectory.create(name: "Other", at: collection, paths: base)
        var a = GameInstance(name: "Custom A", gameVersion: "1.21.1"); a.runDirectory = .custom; a.customRunDirectory = custom
        var b = GameInstance(name: "Custom B", gameVersion: "1.21.1"); b.runDirectory = .custom; b.customRunDirectory = custom; b.directoryID = folder.id
        var state = PersistentState(); state.instances = [a, b]; state.gameDirectories = [folder]
        let saved = try StateStore.save(state, to: base)
        return (base.configured(with: saved), a, b, custom)
    }

    @Test func customRootsKeepGameDataTogetherAndInstanceMetadataSeparate() throws {
        let (paths, a, b, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        #expect(paths.game(a.id) == custom.url && paths.game(b.id) == custom.url)
        #expect(paths.gameDataState(a.id) == paths.gameDataState(b.id))
        #expect(paths.manifest(a.id) != paths.manifest(b.id))
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "original-options")
        let again = try CustomRunDirectory.register(at: custom.url, paths: paths)
        #expect(again.isSameLocation(as: custom))
        #expect(try StateStore.load(paths).schemaVersion == 7)
        var wrong = a; wrong.customRunDirectory = .init(id: UUID(), url: custom.url, bookmark: nil, createdAt: Date())
        #expect(throws: (any Error).self) { try paths.validateBinding(wrong) }
        #expect(throws: (any Error).self) { try a.applyingInstallation(wrong, requested: a) }
        var independent = a; independent.runDirectory = .isolated
        #expect(paths.including(independent).game(a.id) == paths.instance(a.id).appendingPathComponent("minecraft"))
    }

    @Test func missingOrReplacedLocationDoesNotCreateAFallbackGame() throws {
        let (paths, a, _, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let moved = custom.url.deletingLastPathComponent().appendingPathComponent("Moved game")
        try FileManager.default.moveItem(at: custom.url, to: moved)
        #expect(try StateStore.load(paths).instances.count == 2) // an offline game does not make the whole index unreadable
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: a.id) }
        #expect(!FileManager.default.fileExists(atPath: custom.url.path))
        #expect(!FileManager.default.fileExists(atPath: paths.instance(a.id).appendingPathComponent("minecraft").path))
        try FileManager.default.createDirectory(at: custom.url, withIntermediateDirectories: false)
        try Data("foreign".utf8).write(to: custom.url.appendingPathComponent("options.txt"))
        _ = try CustomRunDirectory.register(at: custom.url, paths: LauncherPaths(root: paths.root))
        #expect(throws: (any Error).self) { try paths.validateInstanceLocation(a.id) }
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "foreign")
        let relocated = try custom.relocated(to: moved, paths: paths)
        #expect(relocated.id == custom.id)
        #expect(try String(contentsOf: relocated.url.appendingPathComponent("options.txt"), encoding: .utf8) == "original-options")
    }

    @Test func registrationRejectsManagedOverlapNestedRootsCopiesAndEscapingMarkers() throws {
        let (paths, a, _, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        #expect(throws: (any Error).self) { try CustomRunDirectory.register(at: paths.root, paths: paths) }
        #expect(throws: (any Error).self) { try CustomRunDirectory.register(at: paths.root.deletingLastPathComponent(), paths: paths) }
        let nested = custom.url.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try CustomRunDirectory.register(at: nested, paths: paths) }
        let copied = custom.url.deletingLastPathComponent().appendingPathComponent("Copied game")
        try FileManager.default.copyItem(at: custom.url, to: copied)
        #expect(throws: (any Error).self) { try CustomRunDirectory.register(at: copied, paths: paths) }
        let escaping = custom.url.deletingLastPathComponent().appendingPathComponent("Escaping")
        try FileManager.default.createDirectory(at: escaping, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: escaping.appendingPathComponent(".ruri"), withDestinationURL: paths.cache)
        #expect(throws: (any Error).self) { try CustomRunDirectory.register(at: escaping, paths: paths) }
        var missing = a; missing.customRunDirectory = nil
        var state = try StateStore.load(paths); state.instances[0] = missing
        #expect(throws: (any Error).self) { try StateStore.save(state, to: paths) }
    }

    @Test func resolvingOneMovedLocationUpdatesEveryReferenceWithoutChangingPreferences() throws {
        let (paths, a, b, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let moved = custom.url.deletingLastPathComponent().appendingPathComponent("Relocated")
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let location = try custom.relocated(to: moved, paths: paths)
        var state = try StateStore.load(paths)
        state.instances[0].customRunDirectory = location
        state.instances[1].customRunDirectory?.bookmark = nil
        let resolved = state.resolvingCustomRunDirectoryBookmarks()
        #expect(resolved.instances[0].customRunDirectory == resolved.instances[1].customRunDirectory)
        #expect(resolved.instances.map(\.id) == [a.id, b.id])
        #expect(resolved.instances[1].directoryID == b.directoryID && resolved.settings == state.settings)
        try paths.configured(with: resolved).validateDirectoryConfiguration()
    }

    @Test func customInstancesShareContentBackupsAndOneWriterAcrossCollections() async throws {
        let (paths, a, b, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        var lease: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: a.id)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: b.id) }
        let isolated = GameInstance(name: "Separate", gameVersion: "1.21.1")
        let independent = try GameRunLease.acquire(paths: paths.including(isolated), instanceID: isolated.id)
        withExtendedLifetime([lease, independent]) {}; lease = nil
        let source = paths.cache.appendingPathComponent("fixture.jar"); try Data("fixture".utf8).write(to: source)
        let record = ManagedContent(projectID: "fixture", versionID: "v1", title: "Fixture", versionName: "1", kind: .mod, filename: "fixture.jar", size: 7, requiredProjects: [])
        try await ContentManager(paths: paths, instanceID: a.id).install([.init(record: record, source: source)])
        #expect(try await ContentManager(paths: paths, instanceID: b.id).records() == [record])
        let world = paths.game(a.id).appendingPathComponent("saves/World")
        try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
        try WorldTests().nbt().write(to: world.appendingPathComponent("level.dat"))
        let backup = try await WorldManager(paths: paths, instanceID: a.id).backup(folder: "World")
        #expect(try await WorldManager(paths: paths, instanceID: b.id).backups().first?.id == backup.id)
        #expect(!FileManager.default.fileExists(atPath: paths.instance(b.id).appendingPathComponent("content.json").path))
    }

    @Test @MainActor func monitorSnapshotsStripBookmarksAndOldProtocolsCannotUseCustomPaths() throws {
        let (paths, a, _, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let frozen = paths.monitorSnapshot(for: a.id)
        #expect(frozen.game(a.id) == custom.url && frozen.instanceDirectories.count == 1)
        #expect(frozen.instanceCustomDirectories?[a.id]?.bookmark == nil)
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [], directory: custom.url, environment: [:])
        let request = MonitorLaunchRequest(version: 5, root: paths.root, instanceID: a.id, sessionID: UUID(), monitor: identity, plan: plan, secrets: [], storage: frozen)
        #expect(try GameMonitorService.validatedPaths(request).game(a.id) == custom.url)
        let old = MonitorLaunchRequest(version: 4, root: paths.root, instanceID: a.id, sessionID: UUID(), monitor: identity, plan: plan, secrets: [], storage: frozen)
        #expect(throws: (any Error).self) { try GameMonitorService.validatedPaths(old) }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func actualMonitorUsesCustomRootAndRetainsReservation() async throws {
        let (paths, a, b, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let recorder = try GameSessionRecorder(paths: paths, instance: a, accountMode: "offline")
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let helper = repository.appendingPathComponent(".build/validation/out/Products/Debug/ruri-monitor")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "pwd; sleep 1; echo custom-game-finished"], directory: custom.url, environment: ["PATH": "/bin:/usr/bin"])
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: helper)
        try StateStore.update(paths) { $0.selectedDirectoryID = b.directoryID }
        #expect(throws: (any Error).self) { try GameSessionRecorder(paths: paths, instance: b, accountMode: "offline") }
        let completed = try await GameMonitorClient.wait(paths: paths, instanceID: a.id, sessionID: recorder.record.id)
        #expect(completed.exit?.status == 0)
        let log = try GameSessionStore.logTail(paths: paths, session: completed)
        #expect(log.contains(custom.url.path) && log.contains("custom-game-finished"))
        #expect(try GameSessionStore.list(paths: paths, instanceID: b.id).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: custom.url.appendingPathComponent(".ruri/active-session.json").path))
        let next = try GameRunLease.acquire(paths: paths, instanceID: b.id); withExtendedLifetime(next) {}
    }
}
