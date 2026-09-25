import Foundation
import Testing
@testable import RuriCore

struct GameHistoryTests {
    private func session(instance: GameInstance, id: UUID = UUID(), started: Date = Date(), seconds: Double = 30) -> GameSession {
        var record = GameSession(id: id, instanceID: instance.id, instanceName: instance.name, gameVersion: instance.gameVersion, loader: "vanilla", loaderVersion: nil,
                                 memoryMB: 1024, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 123,
                                 createdAt: started, updatedAt: started.addingTimeInterval(seconds), state: .succeeded, stage: .finished, events: [], evidence: [])
        record.exit = .init(status: 0, reason: .exit, processID: 123, startedAt: started, endedAt: started.addingTimeInterval(seconds), stopRequested: false, durationSeconds: seconds)
        return record
    }

    @Test func historyQueriesArePagedAndOlderSnapshotsCannotUndoACompletedRun() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var records: [GameSession] = []
        for index in 0..<12 {
            let record = session(instance: instance, started: Date(timeIntervalSince1970: Double(index) * 60), seconds: 10)
            records.append(record); try GameHistoryStore.record(record, paths: paths)
        }
        var stale = records[0]; stale.state = .running; stale.exit = nil; stale.updatedAt = Date()
        try GameHistoryStore.record(stale, paths: paths)
        #expect(try GameHistoryStore.load(paths: paths, sessionID: stale.id)?.state == .succeeded)
        let first = try GameHistoryStore.list(paths: paths, query: .init(instanceID: instance.id, limit: 5))
        let second = try GameHistoryStore.list(paths: paths, query: .init(instanceID: instance.id, limit: 5, offset: 5))
        #expect(first.count == 5 && second.count == 5 && Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
        #expect(try GameHistoryStore.list(paths: paths, query: .init(search: "1.21.1")).count == 12)
        #expect(try GameHistoryStore.list(paths: paths, query: .init(problemsOnly: true)).isEmpty)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 120)
    }

    @Test func completionUsesRevisionEvenIfTheSystemClockMovesBackwards() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var running = session(instance: instance)
        let exit = running.exit
        running.state = .running; running.exit = nil; running.revision = 1
        try GameHistoryStore.record(running, paths: paths)
        var ended = running
        ended.state = .succeeded; ended.exit = exit; ended.revision = 2
        ended.updatedAt = running.updatedAt.addingTimeInterval(-3600)
        try GameHistoryStore.record(ended, paths: paths)
        #expect(try GameHistoryStore.load(paths: paths, sessionID: ended.id)?.state == .succeeded)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 30)
    }

    @Test func clockExcludesSleepAndSplitsMidnightWithoutTrustingWallTime() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2025-01-01T23:59:30Z"))
        var clock = GameTimingAccumulator(startedAt: start, timeZone: TimeZone(secondsFromGMT: 0)!)
        _ = clock.sample(at: start.addingTimeInterval(30), awakeSeconds: 30, elapsedSeconds: 30)
        _ = clock.sample(at: start.addingTimeInterval(3630), awakeSeconds: 30, elapsedSeconds: 3630)
        let result = clock.sample(at: start.addingTimeInterval(3660), awakeSeconds: 60, elapsedSeconds: 3660, final: true)
        #expect(result.awakeSeconds == 60 && result.elapsedSeconds == 3660 && result.quality == .complete)
        #expect(result.days.count == 2 && result.days.allSatisfy { $0.seconds == 30 })
        var changedClock = GameTimingAccumulator(startedAt: start)
        let changed = changedClock.sample(at: start.addingTimeInterval(-3600), awakeSeconds: 15, elapsedSeconds: 15, final: true)
        #expect(changed.awakeSeconds == 15 && changed.days.reduce(0) { $0 + $1.seconds } == 15)
    }

    @Test @MainActor func interruptedSessionRetainsOnlyItsConfirmedCheckpoint() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let identity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        var clock = GameTimingAccumulator(startedAt: Date().addingTimeInterval(-60))
        recorder.checkpoint(clock.sample(at: Date(), awakeSeconds: 42, elapsedSeconds: 60))
        var record = recorder.record
        record.state = .running; record.stage = .running
        record.gameIdentity = .init(pid: identity.pid, startSeconds: identity.startSeconds + 1, startMicroseconds: identity.startMicroseconds)
        record.monitorIdentity = record.gameIdentity; record.processID = identity.pid
        try recorder.close()
        record.revision = (record.revision) + 1
        try GameHistoryStore.record(record, paths: paths)
        let recovered = try GameSessionRecovery.finish(paths: paths, expected: record)
        #expect(recovered.exit == nil && recovered.timing?.quality == .interrupted && recovered.playedSeconds == 42)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 42)
        #expect(identity.isAlive)
    }

    @Test @MainActor func knownExitSurvivesAnInterruptedPostCommand() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var record = session(instance: instance)
        let exit = record.exit
        let current = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        let ended = ProcessIdentity(pid: current.pid, startSeconds: current.startSeconds + 1, startMicroseconds: current.startMicroseconds)
        record.state = .running; record.stage = .afterCommand; record.revision = 3
        record.monitorIdentity = ended; record.gameIdentity = ended; record.commandIdentity = ended
        record.commandResults = []
        try GameHistoryStore.record(record, paths: paths)
        let recovered = try GameSessionRecovery.finish(paths: paths, expected: record)
        #expect(recovered.exit == exit && recovered.state == .succeeded && recovered.hasPostCommandFailure)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 30)
    }

    @Test @MainActor func brokenDiagnosticLogDoesNotLoseTheGameResultOrTime() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let output = try recorder.makeOutputCapture(); recorder.retainOutput(output)
        output.receive(Data("bounded evidence\n".utf8)); output.finish()
        // A directory where the console file should be simulates a sink error.
        try FileManager.default.createDirectory(at: recorder.directory.appendingPathComponent("console-tail.log"), withIntermediateDirectories: true)
        try recorder.finish(exit: .init(status: 7, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false, durationSeconds: 15))
        let saved = try #require(try GameHistoryStore.load(paths: paths, sessionID: recorder.record.id))
        #expect(saved.exit?.status == 7 && saved.state == .failed && saved.playedSeconds == 15)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 15)
    }
}
