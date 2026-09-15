import Foundation
import Testing
@testable import RuriCore

struct GameSessionRecoveryTests {
    @MainActor private func fixture(game: ProcessIdentity?) throws -> (LauncherPaths, GameInstance, GameSession) {
        let (paths, instance) = try GameSessionTests().setup()
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.append("original evidence")
        var record = recorder.record
        record.state = .running; record.stage = .running
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        record.monitorIdentity = .init(pid: identity.pid, startSeconds: identity.startSeconds + 1, startMicroseconds: identity.startMicroseconds)
        record.gameIdentity = game; record.processID = game?.pid
        try recorder.close()
        try save(&record, paths: paths)
        return (paths, instance, record)
    }
    private func save(_ record: inout GameSession, paths: LauncherPaths) throws {
        let saved = try GameHistoryStore.load(paths: paths, sessionID: record.id)
        record.revision = (saved?.revision ?? record.revision) + 1
        record.updatedAt = Date()
        try GameHistoryStore.record(record, paths: paths)
    }
    @Test @MainActor func reusedPIDCanRecoverWithoutSignallingOrInventingExit() throws {
        let current = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let old = ProcessIdentity(pid: current.pid, startSeconds: current.startSeconds + 2, startMicroseconds: current.startMicroseconds)
        let (paths, instance, record) = try fixture(game: old)
        defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(GameSessionRecovery.status(record) == .processEnded)
        let result = try GameSessionRecovery.finish(paths: paths, expected: record)
        #expect(result.state == .interrupted && result.exit == nil)
        #expect(result.interruption?.resolution == .knownProcessEnded && result.interruption?.previousStage == .running)
        #expect(result.processID == current.pid && current.isAlive)
        #expect(try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: record.id) == result)
        #expect(!FileManager.default.fileExists(atPath: paths.instance(instance.id).appendingPathComponent("playtime.json").path))
        #expect(try GameSessionStore.logTail(paths: paths, session: result).contains("original evidence"))
        let next = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try next.fail(CancellationError(), cancelled: true)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: result)
        #expect(diagnosis.findings.isEmpty && diagnosis.summary.contains("没有取得实际退出码"))
        let bundle = try GameDiagnosticBundle.preview(session: result, diagnosis: diagnosis)
        #expect(bundle.files.first { $0.id == "environment" }?.text.contains("not exit time") == true)
    }
    @Test @MainActor func missingIdentityRequiresExplicitConfirmationAndLeavesHistory() throws {
        let (paths, instance, record) = try fixture(game: nil)
        defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(GameSessionRecovery.status(record) == .confirmationRequired)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: record) }
        #expect(throws: (any Error).self) { try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline") }
        #expect(try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: record.id) == record)
        let result = try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: true)
        #expect(result.interruption?.resolution == .userConfirmedEnded)
        #expect(result.exit == nil && result.evidence == record.evidence)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: true) }
        let next = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try next.fail(CancellationError(), cancelled: true)
    }
    @Test @MainActor func liveGameMonitorAndKernelLeaseEachPreventRecovery() throws {
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let (paths, instance, record) = try fixture(game: identity)
        defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(GameSessionRecovery.status(record) == .gameRunning)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: true) }
        var monitored = record; monitored.monitorIdentity = identity
        try save(&monitored, paths: paths)
        #expect(GameSessionRecovery.status(monitored) == .monitoring)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: monitored, userConfirmedEnded: true) }
        var unknown = record; unknown.gameIdentity = nil
        try save(&unknown, paths: paths)
        let lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id, ignoringSession: record.id)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: unknown, userConfirmedEnded: true) }
        withExtendedLifetime(lease) {}
        #expect(try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: record.id) == unknown)
        #expect(identity.isAlive)
    }
    @Test @MainActor func changedRecordIsNotOverwrittenByAnOldRecoveryView() throws {
        let (paths, _, record) = try fixture(game: nil)
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var changed = record; changed.failure = "updated elsewhere"; try save(&changed, paths: paths)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: true) }
        #expect(try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id) == changed)
        let beforeExit = changed
        changed.exit = .init(status: 1, reason: .exit, processID: 123, startedAt: record.createdAt, endedAt: Date(), stopRequested: false)
        try save(&changed, paths: paths)
        #expect(throws: (any Error).self) { try GameSessionRecovery.finish(paths: paths, expected: beforeExit, userConfirmedEnded: true) }
        #expect(try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id) == changed)
    }
}
