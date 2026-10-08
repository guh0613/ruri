import Foundation
import Testing
@testable import RuriCore

struct MonitorLeaseBoundaryTests {
    @Test(arguments: [GameRunDirectory.isolated, .shared]) @MainActor
    func designatedMonitorResumesWithoutLoadingLauncherState(mode: GameRunDirectory) throws {
        let (base, original) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: base.root) }
        var instance = original; instance.runDirectory = mode
        let paths = base.including(instance)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let preparation = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let frozen = SessionLocationSnapshot(paths: paths, instanceID: instance.id)
        try preparation.handoff(to: identity)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
        // An unrelated settings writer cannot change the frozen runtime location.
        try Data("not a launcher settings document".utf8).write(to: paths.state)
        var lease: SessionRunLease? = try .resume(paths: frozen, instanceID: instance.id, sessionID: preparation.record.id, monitor: identity)
        #expect(lease != nil)
        #expect(throws: (any Error).self) { try SessionRunFileLease.instance(at: paths.instance(instance.id)) }
        var record = preparation.record; record.state = .failed; record.revision += 1
        try GameHistoryStore.record(record, paths: frozen)
        try lease?.clearReservation(session: record)
        lease = nil
        try FileManager.default.removeItem(at: paths.state)
        let next = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        withExtendedLifetime(next) {}
    }

    @Test @MainActor func missingHandoffWrongIdentityAndPendingTransactionsPreventAdoption() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let frozen = SessionLocationSnapshot(paths: paths, instanceID: instance.id)
        #expect(throws: (any Error).self) { try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: identity) }
        try recorder.handoff(to: identity)
        let wrong = ProcessIdentity(pid: identity.pid, startSeconds: 0, startMicroseconds: 0)
        #expect(throws: (any Error).self) { try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: wrong) }
        let marker = paths.instance(instance.id).appendingPathComponent("run-directory-change")
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) { try SessionRunLease.resume(paths: frozen, instanceID: instance.id, sessionID: recorder.record.id, monitor: identity) }
    }
}
