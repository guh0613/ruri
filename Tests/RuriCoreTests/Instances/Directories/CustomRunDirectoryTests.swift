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

    @Test func registeringTheSameCustomRootPreservesItsIdentityAndContents() throws {
        let (paths, _, _, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let again = try CustomRunDirectory.register(at: custom.url, paths: paths)
        #expect(again.isSameLocation(as: custom))
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "original-options")
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

    @Test func customInstancesInDifferentCollectionsShareContentRecords() async throws {
        let (paths, a, b, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let source = paths.cache.appendingPathComponent("fixture.jar"); try Data("fixture".utf8).write(to: source)
        let record = ManagedContent(projectID: "fixture", versionID: "v1", title: "Fixture", versionName: "1", kind: .mod, filename: "fixture.jar", size: 7, requiredProjects: [])
        try await ContentManager(paths: paths, instanceID: a.id).install([.init(record: record, source: source)])
        #expect(try await ContentManager(paths: paths, instanceID: b.id).records() == [record])
    }

    @Test @MainActor func monitorSnapshotsStripBookmarksAndRejectOtherProtocols() throws {
        let (paths, a, _, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let frozen = paths.monitorSnapshot(for: a.id)
        #expect(frozen.instanceCustomDirectories?[a.id]?.bookmark == nil)
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [], directory: custom.url, environment: [:])
        let request = MonitorLaunchRequest(version: MonitorLaunchRequest.currentVersion, instanceID: a.id, sessionID: UUID(), monitor: identity, plan: plan, secrets: [], storage: frozen)
        #expect(try GameMonitorService.validatedPaths(request).game(a.id) == custom.url)
        let old = MonitorLaunchRequest(version: MonitorLaunchRequest.currentVersion + 1, instanceID: a.id, sessionID: UUID(), monitor: identity, plan: plan, secrets: [], storage: frozen)
        #expect(throws: (any Error).self) { try GameMonitorService.validatedPaths(old) }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func monitorRetainsCustomRootAndExternalMetadataAfterSelectionChanges() async throws {
        let (paths, a, b, custom) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let selected = try StateStore.update(paths) { $0.selectedDirectoryID = b.directoryID }
        let selectedPaths = paths.configured(with: selected)
        let recorder = try GameSessionRecorder(paths: selectedPaths, instance: b, accountMode: "offline")
        let helper = TestPaths.monitorExecutable
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "pwd; sleep 1; echo custom-game-finished"], directory: custom.url, environment: ["PATH": "/bin:/usr/bin"], debugLogging: true)
        try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: selectedPaths, secrets: [], helper: helper)
        let changed = try StateStore.update(paths) { $0.selectedDirectoryID = nil }
        let reconnected = paths.configured(with: changed)
        #expect(throws: (any Error).self) { try GameSessionRecorder(paths: paths, instance: a, accountMode: "offline") }
        let completed = try await GameMonitorClient.wait(paths: reconnected, instanceID: b.id, sessionID: recorder.record.id)
        #expect(completed.exit?.status == 0)
        #expect(!FileManager.default.fileExists(atPath: LauncherPaths(root: paths.root).instance(b.id).path))
        let log = try GameSessionStore.logTail(paths: reconnected, session: completed)
        #expect(log.contains(custom.url.path) && log.contains("custom-game-finished"))
        #expect(try GameSessionStore.list(paths: paths, instanceID: a.id).isEmpty)
        let next = try GameRunLease.acquire(paths: paths, instanceID: a.id); withExtendedLifetime(next) {}
    }
}
