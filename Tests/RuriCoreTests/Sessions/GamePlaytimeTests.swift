import Foundation
import Testing
@testable import RuriCore

struct GamePlaytimeTests {
    @Test @MainActor func monitorPlaytimeIsCountedOnceAndPreservesLegacyTotal() throws {
        let (paths, original) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = original; instance.playTime = 120
        let first = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let now = Date()
        try first.finish(exit: .init(status: 0, reason: .exit, processID: 123, startedAt: now, endedAt: now.addingTimeInterval(-60), stopRequested: false, durationSeconds: 12))
        #expect(try GamePlaytimeStore.load(paths: paths, instanceID: instance.id)?.total == 132)
        try GamePlaytimeStore.record(first.record, paths: paths)
        #expect(try GamePlaytimeStore.load(paths: paths, instanceID: instance.id)?.total == 132)
        let second = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try second.finish(exit: .init(status: 143, reason: .exit, processID: 124, startedAt: now, endedAt: now.addingTimeInterval(20), stopRequested: true, durationSeconds: 20))
        #expect(try GamePlaytimeStore.load(paths: paths, instanceID: instance.id)?.total == 152)
    }
    @Test @MainActor func cursorReplaysHistoryAndIncrementalOutputWithoutDuplicatingIt() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.append("before reconnection")
        let cursor = try GameSessionLogCursor(paths: paths, session: recorder.record)
        try recorder.append("during reconnection")
        #expect(try await cursor.refresh())
        try recorder.append("after reconnection")
        #expect(try await cursor.refresh())
        #expect(try await !cursor.refresh())
        let lines = await cursor.lines
        #expect(lines.filter { $0 == "before reconnection" }.count == 1)
        #expect(lines.filter { $0 == "during reconnection" }.count == 1)
        #expect(lines.filter { $0 == "after reconnection" }.count == 1)
        try recorder.fail(CancellationError(), cancelled: true)
    }
}
