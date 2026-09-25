import Foundation
import Testing
@testable import RuriCore

struct GameSessionStorageTests {
    @Test(.timeLimit(.minutes(1))) @MainActor func runningGamePersistsCheckpointsBeforeItsFinalResult() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let end = paths.root.appendingPathComponent("finish-game")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"),
                              arguments: ["-c", #"i=0; while [ ! -f "$1" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i+1)); done"#, "checkpoint-fixture", end.path],
                              directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        let coordinator = GameSessionCoordinator(plan: plan, recorder: recorder, paths: paths, checkpointInterval: .milliseconds(50), checkpointLeeway: .milliseconds(5))
        let run = Task { try await coordinator.run() }
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            var saved = recorder.record
            repeat {
                try await Task.sleep(for: .milliseconds(25))
                saved = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
            } while saved.playedSeconds < 0.1 && !saved.state.isFinished && ContinuousClock.now < deadline
            #expect(saved.state == .running && saved.exit == nil && saved.playedSeconds >= 0.1)
            FileManager.default.createFile(atPath: end.path, contents: nil)
            #expect(try await run.value == 0)
        } catch {
            FileManager.default.createFile(atPath: end.path, contents: nil)
            _ = try? await run.value
            throw error
        }
        #expect(recorder.record.timing?.quality == .complete)
    }

    @Test @MainActor func cancellationStillPersistsTheResultAndRollsBackTransactions() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let work = Task { @MainActor in
            #expect(Task.isCancelled)
            try recorder.fail(CancellationError(), cancelled: true)
            do {
                try GameHistoryStore.withDatabase(paths: paths) { db in
                    try db.transaction {
                        try db.execute("UPDATE sessions SET name='uncommitted' WHERE id=?", [.text(recorder.record.id.uuidString)])
                        throw CancellationError()
                    }
                }
            } catch is CancellationError { }
        }
        work.cancel()
        try await work.value
        let saved = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(saved.state == .cancelled && saved.finalSnapshot && saved.instanceName == instance.name)
        let next = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try next.fail(CancellationError(), cancelled: true)
        #expect(try GameHistoryStore.list(paths: paths).count == 2)
    }

}
