import Foundation
import Testing
@testable import RuriCore

struct GameActivityTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func timing(_ seconds: Double, awake: Double? = nil) -> GameSessionTiming {
        var clock = GameTimingAccumulator(startedAt: start, timeZone: TimeZone(secondsFromGMT: 0)!)
        return clock.sample(at: start.addingTimeInterval(seconds), awakeSeconds: awake ?? seconds, elapsedSeconds: seconds)
    }
    private func activity() throws -> GameActivityTracking {
        var tracker = GameActivityAccumulator(timing: timing(0))
        tracker.change(to: .server(address: try ServerAddress("example.test"), name: "Example"), source: .quickPlay, timing: timing(10))
        tracker.change(to: .world(folder: "World", name: "World"), source: .quickPlay, timing: timing(40))
        tracker.finish(timing(60))
        return tracker.tracking
    }
    @Test func transitionsAttributeEachAwakeSecondOnce() throws {
        let result = try activity()
        #expect(result.valid(total: 60))
        #expect(result.segments.map(\.seconds) == [10,30,20])
        #expect(result.attributedSeconds == 50 && result.unattributedSeconds == 10)
        #expect(result.segments[1].quality == .estimated)
    }
    @Test func sleepMidnightAndDrainDoNotInflateAttribution() throws {
        let date = Date(timeIntervalSince1970: Double(1_800_000_000 - 1_800_000_000 % 86400 + 86390))
        var clock = GameTimingAccumulator(startedAt: date, timeZone: TimeZone(secondsFromGMT: 0)!)
        var tracker = GameActivityAccumulator(timing: clock.sample(at: date, awakeSeconds: 0, elapsedSeconds: 0))
        tracker.change(to: .server(address: try ServerAddress("localhost"), name: "Local"), source: .quickPlay, timing: clock.timing)
        tracker.sample(clock.sample(at: date.addingTimeInterval(5), awakeSeconds: 5, elapsedSeconds: 5))
        tracker.sample(clock.sample(at: date.addingTimeInterval(3605), awakeSeconds: 5, elapsedSeconds: 3605))
        tracker.sample(clock.sample(at: date.addingTimeInterval(3625), awakeSeconds: 25, elapsedSeconds: 3625))
        tracker.finish(clock.timing, maximumSeconds: 24)
        #expect(tracker.tracking.valid(total: 24))
        #expect(tracker.tracking.attributedSeconds == 24)
        #expect(tracker.tracking.segments.last?.days.map(\.seconds) == [5,19])
    }
    @Test func nativeQuickPlayFormatRejectsPartialStaleAndInvalidRecords() throws {
        let date = start.addingTimeInterval(2).ISO8601Format()
        let data = try JSONSerialization.data(withJSONObject: [["type":"multiplayer", "id":"example.test:25565", "name":"Example", "lastPlayedTime":date, "gamemode":"survival"]])
        #expect(QuickPlayVisit.read(data, startedAt: start, now: start.addingTimeInterval(3))?.target.key == "example.test:25565")
        #expect(QuickPlayVisit.read(Data(data.dropLast()), startedAt: start, now: start.addingTimeInterval(3)) == nil)
        #expect(QuickPlayVisit.read(data, startedAt: start.addingTimeInterval(10), now: start.addingTimeInterval(20)) == nil)
        #expect(QuickPlayVisit.read(Data("[]".utf8), startedAt: start, now: start) == nil)
    }
    @Test func connectionAttemptsAndChatNeverProveEntry() {
        var parser = GameActivityLogParser(version: "1.12.2")
        let events = parser.consume(Data("[12:34:56] [Client thread/INFO]: Connecting to example.test, 25565\n[12:34:57] [Client thread/INFO]: [CHAT] Loaded 5 advancements\n".utf8))
        #expect(events.count == 1)
        if case .connecting(let address) = events.first { #expect(address.key == "example.test:25565") } else { Issue.record("Expected only a connection attempt") }
        #expect(parser.consume(Data("[Client thread/INFO] Loaded 12 advancements\n".utf8)).count == 1)
        let stop = parser.consume(Data("[Client thread/INFO] Stopping!\n".utf8))
        if case .left(let explicit) = stop.first { #expect(!explicit) } else { Issue.record("Expected an estimated exit boundary") }
        var old = GameActivityLogParser(version: "1.8.9")
        #expect(old.consume(Data("[Client thread/INFO] Loaded 12 advancements\n".utf8)).isEmpty)
    }
    @Test func segmentsMigrateAlongsideLegacyHistoryAndCheckpointIdempotently() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var record = GameSession(id: UUID(), instanceID: instance.id, instanceName: instance.name, gameVersion: "1.21.1", loader: "vanilla", loaderVersion: nil,
                                 memoryMB: 2048, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 1,
                                 createdAt: start, updatedAt: start.addingTimeInterval(60), state: .running, stage: .running, events: [], evidence: [])
        record.timing = timing(60); record.activity = try activity(); record.revision = 2
        record.world = .init(folder: "World", name: "World", source: .detected)
        try GameHistoryStore.record(record, paths: paths)
        record.revision = 3
        try GameHistoryStore.checkpoint(record, paths: paths)
        try GameHistoryStore.checkpoint(record, paths: paths)
        var stale = record; stale.revision = 1; stale.activity?.segments = []
        // A valid older snapshot must not replace the indexed segments.
        stale.activity = nil; stale.timing = timing(0)
        try GameHistoryStore.record(stale, paths: paths)
        let summaries = try GameActivityStore.servers(paths: paths)
        #expect(summaries.count == 1 && summaries[0].seconds == 30 && summaries[0].visits == 1)
        #expect(try GameActivityStore.days(paths: paths, server: ServerAddress("example.test")).reduce(0) { $0 + $1.seconds } == 30)
        #expect(try GameHistoryStore.list(paths: paths, query: .init(serverAddress: ServerAddress("example.test"))).count == 1)
        #expect(try GameHistoryStore.list(paths: paths, query: .init(worldFolder: "World")).count == 1)
        #expect(try GameHistoryStore.list(paths: paths, query: .init(search: "example.test")).count == 1)
        #expect(try GameHistoryStore.overview(paths: paths, range: .all).worlds.first?.seconds == 20)
        let restored = try #require(try GameHistoryStore.load(paths: paths, sessionID: record.id))
        #expect(restored.activity?.valid(total: restored.playedSeconds) == true)
        var interrupted = restored; interrupted.activity?.interrupt()
        #expect(interrupted.activity?.attributedSeconds == 50 && interrupted.activity?.complete == true)
        var legacy = record
        legacy = .init(id: UUID(), instanceID: instance.id, instanceName: instance.name, gameVersion: "1.12.2", loader: "vanilla", loaderVersion: nil,
                       memoryMB: 2048, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 1, createdAt: start,
                       updatedAt: start.addingTimeInterval(100), state: .succeeded, stage: .finished, events: [], evidence: [])
        legacy.timing = timing(100); legacy.world = .init(folder: "World", name: "World", source: .detected)
        try GameHistoryStore.record(legacy, paths: paths)
        #expect(try GameHistoryStore.overview(paths: paths, range: .all).worlds.first?.seconds == 120)
        #expect(try GameHistoryStore.summary(paths: paths).seconds == 160)
    }
    @Test(.timeLimit(.minutes(1))) @MainActor func monitorPersistsQuickPlayBeforeExitAndDoesNotReassignWholeRun() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let end = paths.root.appendingPathComponent("finish-game"), log = paths.instance(instance.id).appendingPathComponent("quick-play/test.json")
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", #"i=0; while [ ! -f "$1" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i+1)); done"#, "activity-fixture", end.path], directory: paths.game(instance.id), environment: ["PATH":"/bin:/usr/bin"], quickPlayLog: log)
        let coordinator = GameSessionCoordinator(plan: plan, recorder: recorder, paths: paths, checkpointInterval: .milliseconds(50), checkpointLeeway: .milliseconds(5))
        let run = Task { try await coordinator.run() }
        do {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while recorder.record.timing == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            let data = try JSONSerialization.data(withJSONObject: [["type":"multiplayer","id":"example.test","name":"Fixture","lastPlayedTime":Date().ISO8601Format(.init(includingFractionalSeconds: true)),"gamemode":"survival"]])
            try data.write(to: log)
            while recorder.record.activity?.segments.contains(where: { $0.target.kind == "server" }) != true && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(25)) }
            #expect(recorder.record.activity?.segments.contains { $0.target.kind == "server" } == true)
            try await Task.sleep(for: .milliseconds(150))
            #expect(try GameActivityStore.servers(paths: paths).first?.seconds ?? 0 > 0)
            try Data().write(to: end)
            #expect(try await run.value == 0)
        } catch { try? Data().write(to: end); _ = try? await run.value; throw error }
        #expect(recorder.record.activity?.valid(total: recorder.record.playedSeconds) == true)
        #expect(recorder.record.activity?.complete == true && recorder.record.world == nil)
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }
}
