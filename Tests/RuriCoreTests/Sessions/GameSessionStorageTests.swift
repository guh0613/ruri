import Foundation
import Testing
@testable import RuriCore

struct GameSessionStorageTests {
    @Test @MainActor func checkpointsOnlyUpdateTimingAndNoRuntimeFilesAreCreated() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.started(processID: 123)
        func context() throws -> Data {
            try GameHistoryStore.withDatabase(paths: paths) { db in
                var data = Data()
                try db.rows("SELECT payload FROM sessions WHERE id=?", [.text(recorder.record.id.uuidString)]) { data = HistoryDatabase.data($0, 0) ?? Data() }
                return data
            }
        }
        let original = try context()
        var clock = GameTimingAccumulator(startedAt: Date().addingTimeInterval(-120))
        for seconds in [60.0, 120.0] {
            recorder.checkpoint(clock.sample(at: Date(), awakeSeconds: seconds, elapsedSeconds: seconds))
            let saved = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
            #expect(saved == recorder.record && saved.playedSeconds == seconds)
            #expect(try context() == original)
        }
        try recorder.finish(exit: .init(status: 0, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false, durationSeconds: 121))
        #expect(!FileManager.default.fileExists(atPath: recorder.directory.path))
        #expect(!FileManager.default.fileExists(atPath: paths.instance(instance.id).appendingPathComponent("last-exit.json").path))
        #expect(try GameHistoryStore.list(paths: paths).count == 1)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 121)
    }

    @Test @MainActor func dispatchCheckpointActuallyFiresWithoutInheritingActorIsolation() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], directory: paths.game(instance.id), environment: [:])
        let coordinator = GameSessionCoordinator(plan: plan, recorder: recorder, paths: paths, checkpointInterval: .milliseconds(50), checkpointLeeway: .milliseconds(5))
        // Observe actual narrow SQL updates without replacing the recorder's
        // transport callback or relying on a fixed main-actor wakeup deadline.
        try GameHistoryStore.withDatabase(paths: paths) { db in
            try db.execute("CREATE TABLE checkpoint_probe(seconds REAL NOT NULL)")
            try db.execute("CREATE TRIGGER checkpoint_probe_insert AFTER UPDATE OF timing ON sessions WHEN NEW.payload=OLD.payload BEGIN INSERT INTO checkpoint_probe VALUES(NEW.seconds); END")
        }
        let status = try await coordinator.run()
        let count = try GameHistoryStore.withDatabase(paths: paths) { try $0.scalar("SELECT count(*) FROM checkpoint_probe WHERE seconds>0.05") }
        #expect(count > 0 && status == 0)
        #expect(recorder.record.timing?.quality == .complete && recorder.record.playedSeconds >= 4.9)
        #expect(!FileManager.default.fileExists(atPath: recorder.directory.path))
    }

    @Test @MainActor func clientEventsAndReadMarkersShareTheDatabaseWithoutChangingTheSession() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try GameMonitorClient.recordEvent(.connected, paths: paths, session: recorder.record)
        try GameMonitorClient.recordEvent(.windowClosed, paths: paths, session: recorder.record)
        #expect(try GameSessionEventStore.entries(paths: paths, sessionID: recorder.record.id).count == 2)
        #expect(try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) == recorder.record)
        try recorder.fail(RuriError.message("fixture"), cancelled: false)
        try GameSessionReviewStore.mark(recorder.record, paths: paths)
        #expect(try GameSessionReviewStore.contains(recorder.record, paths: paths))
        #expect(!FileManager.default.fileExists(atPath: recorder.directory.path))
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
