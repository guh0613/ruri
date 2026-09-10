import Foundation
import Testing
@testable import RuriCore

struct GameNormalQuitTests {
    @Test func normalRequestDoesNotHideASubsequentFailure() {
        let now = Date()
        let failed = GameExit(status: 1, reason: .exit, processID: 123, startedAt: now, endedAt: now, stopRequested: false, normalQuitRequested: true)
        #expect(failed.requiresAttention && !failed.stoppedByLauncher)
        let signal = GameExit(status: 15, reason: .signal, processID: 123, startedAt: now, endedAt: now, stopRequested: false, normalQuitRequested: true)
        #expect(signal.requiresAttention && !signal.stoppedByLauncher)
        let success = GameExit(status: 0, reason: .exit, processID: 123, startedAt: now, endedAt: now, stopRequested: false, normalQuitRequested: true)
        #expect(success.succeeded && !success.stopRequested && !success.stoppedByLauncher)
        #expect(success.explanation.contains("正常退出请求"))
    }
    @Test @MainActor func requestsMustMatchTheSessionAndRetainSeparateOutcome() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.setNativeQuitSupported(false)
        #expect(throws: (any Error).self) { try GameMonitorClient.requestNormalQuit(paths: paths, record: recorder.record) }
        let requestFile = recorder.directory.appendingPathComponent("quit-request.json")
        func write(sessionID: UUID, version: Int = 1, date: Date = Date()) throws {
            try JSONEncoder().encode(GameNormalQuitRequest(version: version, id: UUID(), sessionID: sessionID, requestedAt: date)).write(to: requestFile)
        }
        try write(sessionID: UUID())
        #expect(GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record) == nil)
        try write(sessionID: recorder.record.id, version: 2)
        #expect(GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record) == nil)
        try write(sessionID: recorder.record.id, date: recorder.record.createdAt.addingTimeInterval(-1))
        #expect(GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record) == nil)
        try write(sessionID: recorder.record.id)
        let request = try #require(GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record))
        try recorder.recordNormalQuit(request, accepted: true)
        #expect(recorder.record.stage == .quitting && recorder.record.exit == nil && !recorder.record.state.isFinished)
        try recorder.fail(RuriError.message("later error"), cancelled: false)
        #expect(recorder.record.state == .failed && recorder.record.normalQuitAttempt?.accepted == true)
        try Data(repeating: 65, count: 2049).write(to: requestFile)
        #expect(GameMonitorClient.normalQuitRequest(directory: recorder.directory, session: recorder.record) == nil)
    }
    @MainActor private func waitFor(_ condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while try !condition() {
            guard Date() < deadline else { throw RuriError.message("退出请求验证超时") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    @Test(.timeLimit(.minutes(1))) @MainActor func unavailableRequestNeverEscalatesAndIsConsumedOnce() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", #"trap 'printf "explicit-stop\n"; exit 0' TERM; while :; do sleep 0.05; done"#], directory: paths.game(instance.id), environment: ["PATH": "/usr/bin:/bin"], nativeQuitSupported: true)
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        func load() throws -> GameSession { try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) }
        defer { if let record = try? load() { try? GameMonitorClient.requestStop(paths: paths, record: record) } }
        try await waitFor { try load().gameIdentity?.isAlive == true }
        let requestID = try GameMonitorClient.requestNormalQuit(paths: paths, record: load())
        try await waitFor { try load().normalQuitAttempt?.requestID == requestID }
        let pending = try load()
        #expect(pending.normalQuitAttempt?.accepted == false && pending.exit == nil)
        try await Task.sleep(for: .milliseconds(650))
        let stillRunning = try load()
        #expect(stillRunning.gameIdentity?.isAlive == true && stillRunning.monitorIdentity?.isAlive == true)
        #expect(stillRunning.events.filter { $0.message.contains("没有成功发送正常退出请求") }.count == 1)
        #expect(!FileManager.default.fileExists(atPath: recorder.directory.appendingPathComponent("stop-request.json").path))
        try GameMonitorClient.requestStop(paths: paths, record: stillRunning)
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.exit?.stopRequested == true && finished.exit?.normalQuitRequested != true)
        #expect(finished.normalQuitAttempt?.requestID == requestID)
    }
    @Test @MainActor func reusedPIDDoesNotReceiveNormalQuit() throws {
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let stale = ProcessIdentity(pid: identity.pid, startSeconds: identity.startSeconds + 1, startMicroseconds: identity.startMicroseconds)
        #expect(!NativeGameQuit.request(stale))
        #expect(identity.isAlive)
    }
}
