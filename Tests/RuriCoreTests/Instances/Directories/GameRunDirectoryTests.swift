import Foundation
import Testing
@testable import RuriCore

struct GameRunDirectoryTests {
    private func fixture() throws -> (LauncherPaths, GameInstance, GameInstance, GameInstance) {
        let base = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-shared-\(UUID())"))
        var a = GameInstance(name: "Shared A", gameVersion: "1.21.1"); a.runDirectory = .shared
        var b = GameInstance(name: "Shared B", gameVersion: "26.2"); b.runDirectory = .shared
        let isolated = GameInstance(name: "Isolated", gameVersion: "1.21.1")
        var state = PersistentState(); state.instances = [a, b, isolated]
        let paths = base.configured(with: state); try paths.prepare()
        return (paths, a, b, isolated)
    }

    @Test func changingTheDefaultIsolationPolicyDoesNotMoveExistingInstances() throws {
        let (paths, a, b, isolated) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var state = PersistentState()
        state.instances = [a, b, isolated]
        state.settings.isolationPolicy = .never
        let changed = paths.configured(with: state)
        #expect(changed.game(isolated.id) == paths.game(isolated.id))
        #expect(changed.game(a.id) == changed.game(b.id))
        #expect(changed.game(isolated.id) != changed.game(a.id))
    }

    @Test func sharedInstancesCannotAcquireTheSameGameButIsolatedOneCanRun() throws {
        let (paths, a, b, isolated) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var first: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: a.id)
        #expect(GameRunLease.isHeld(paths: paths, instanceID: b.id))
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: b.id) }
        let separate = try GameRunLease.acquire(paths: paths, instanceID: isolated.id)
        withExtendedLifetime(first) {}; first = nil
        let second = try GameRunLease.acquire(paths: paths, instanceID: b.id)
        withExtendedLifetime([separate, second]) {}
    }

    @Test @MainActor func reservationProtectsHandoffAndClearsBeforeFinishedInstanceIsRemoved() throws {
        let (paths, a, b, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: a, accountMode: "offline")
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        try recorder.handoff(to: identity)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: b.id) }
        let monitor = try GameSessionRecorder(resuming: recorder.record.id, instanceID: a.id, paths: paths, monitor: identity)
        try monitor.fail(RuriError.message("controlled preparation failure"), cancelled: false)
        try FileManager.default.removeItem(at: paths.instance(a.id))
        let next = try GameRunLease.acquire(paths: paths, instanceID: b.id)
        withExtendedLifetime(next) {}
    }

    @Test @MainActor func unconfirmedPreparationBlocksOtherInstancesUntilExplicitRecovery() throws {
        let (paths, a, b, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: a, accountMode: "offline")
        try recorder.close()
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: b.id) }
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: recorder.record) }
        let recovered = try GameSessionRecovery.finish(paths: paths, expected: recorder.record, userConfirmedEnded: true)
        #expect(recovered.state == .interrupted && recovered.exit == nil)
        let next = try GameRunLease.acquire(paths: paths, instanceID: b.id)
        withExtendedLifetime(next) {}
    }

    @Test func contentChangesAreVisibleToOtherSharedInstances() async throws {
        let (paths, a, b, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let source = paths.cache.appendingPathComponent("fixture.jar"); let data = Data("fixture-content".utf8)
        try data.write(to: source)
        let record = ManagedContent(projectID: "fixture", versionID: "v1", title: "Fixture", versionName: "1", kind: .mod, filename: "fixture.jar", size: Int64(data.count), requiredProjects: [])
        let first = ContentManager(paths: paths, instanceID: a.id), second = ContentManager(paths: paths, instanceID: b.id)
        try await first.install([ContentInstallation(record: record, source: source)])
        #expect(try await second.records() == [record])
        let file = try #require(try await second.scan(.mod).first)
        try await second.setEnabled(false, file: file)
        #expect(try await first.scan(.mod).first?.enabled == false)
        #expect(try await first.records().first?.enabled == false)
    }

    @Test func recoveryCannotRollBackAnotherClientsLiveContentTransaction() async throws {
        let (paths, a, b, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let lock = GameDataOperationLock()
        try lock.acquire(directory: paths.gameDataState(a.id), name: ".content-operation.lock"); defer { lock.release() }
        let transaction = paths.gameDataState(a.id).appendingPathComponent("content-transaction")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: true)
        try Data().write(to: transaction.appendingPathComponent("committed"))
        await #expect(throws: (any Error).self) { try await ContentManager(paths: paths, instanceID: b.id).recover() }
        #expect(FileManager.default.fileExists(atPath: transaction.path))
        let worldLock = GameDataOperationLock()
        try worldLock.acquire(directory: paths.gameDataState(a.id), name: ".world-operation.lock"); defer { worldLock.release() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths, instanceID: b.id).recover() }
    }

    @Test func exportedSharedGameDoesNotContainCoordinationFilesAndImportsIsolated() async throws {
        let (paths, a, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let lease = try GameRunLease.acquire(paths: paths, instanceID: a.id)
        defer { withExtendedLifetime(lease) {} }
        try Data("game-settings".utf8).write(to: paths.game(a.id).appendingPathComponent("options.txt"))
        let transfer = InstanceTransfer(paths: paths), zip = paths.cache.appendingPathComponent("portable.zip")
        try await transfer.export(a, to: zip)
        let prepared = try await transfer.prepare(zip)
        #expect(prepared.instance.runDirectory == nil || prepared.instance.runDirectory == .isolated)
        #expect(FileManager.default.fileExists(atPath: prepared.game.appendingPathComponent("options.txt").path))
        #expect(!FileManager.default.fileExists(atPath: prepared.game.appendingPathComponent(".ruri").path))
        await transfer.discard(prepared)
    }
}
