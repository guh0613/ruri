import Foundation
import Testing
@testable import RuriCore

struct GameSessionTests {
    @Test @MainActor func reviewingLiveLogsDoesNotAcknowledgeLaterFailure() throws {
        let (paths, instance) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try GameSessionReviewStore.mark(recorder.record, paths: paths)
        #expect(try !GameSessionReviewStore.contains(recorder.record, paths: paths))
        try recorder.fail(RuriError.message("failure"), cancelled: false)
        try GameSessionReviewStore.mark(recorder.record, paths: paths, at: recorder.record.updatedAt.addingTimeInterval(1))
        #expect(try GameSessionReviewStore.contains(recorder.record, paths: paths))
        var later = recorder.record; later.updatedAt = later.updatedAt.addingTimeInterval(60)
        #expect(try !GameSessionReviewStore.contains(later, paths: paths))
        try Data(repeating: 1, count: 1025).write(to: recorder.directory.appendingPathComponent("reviewed"))
        #expect(throws: (any Error).self) { try GameSessionReviewStore.contains(recorder.record, paths: paths) }
    }
    func setup() throws -> (LauncherPaths, GameInstance) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try paths.prepare()
        let instance = GameInstance(name: "会话测试", gameVersion: "1.21.1")
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        return (paths, instance)
    }
    @Test @MainActor func preparationFailureAndNextRunHaveIndependentRedactedLogs() throws {
        let (paths, instance) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let failed = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "microsoft")
        failed.addSecrets(["private-refresh-value"])
        try failed.transition(.account)
        try failed.fail(RuriError.message("Refresh failed: private-refresh-value"), cancelled: false)
        let oldLog = try GameSessionStore.logTail(paths: paths, session: failed.record)
        #expect(!oldLog.contains("private-refresh-value") && oldLog.contains("<redacted>"))
        #expect(failed.record.stage == .account && failed.record.title == "验证账号失败")
        let next = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try next.transition(.java); try next.setJava("Java 21")
        try next.started(processID: 123)
        try next.append("Second run output")
        let exit = GameExit(status: 0, reason: .exit, processID: 123, startedAt: next.record.createdAt, endedAt: Date(), stopRequested: false)
        try next.finish(exit: exit)
        let list = try GameSessionStore.list(paths: paths, instanceID: instance.id)
        #expect(list.count == 2 && Set(list.map(\.id)).count == 2)
        #expect(try GameSessionStore.logTail(paths: paths, session: failed.record) == oldLog)
        #expect(try !GameSessionStore.logTail(paths: paths, session: next.record).contains("Refresh failed"))
        let persisted = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: next.record.id)
        #expect(persisted.exit == exit && persisted.java == "Java 21" && persisted.state == .succeeded)
    }
    @Test @MainActor func evidenceCopiesSurviveNextGameLogAndSkipOldReports() throws {
        let (paths, instance) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let game = paths.game(instance.id)
        for directory in ["logs", "crash-reports"] { try FileManager.default.createDirectory(at: game.appendingPathComponent(directory), withIntermediateDirectories: true) }
        let latest = game.appendingPathComponent("logs/latest.log")
        try "Authorization: Bearer private-bearer".write(to: latest, atomically: true, encoding: .utf8)
        let current = game.appendingPathComponent("crash-reports/crash-current.txt")
        try "current failure".write(to: current, atomically: true, encoding: .utf8)
        let old = game.appendingPathComponent("crash-reports/crash-old.txt")
        try "old failure".write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: recorder.record.createdAt.addingTimeInterval(-60)], ofItemAtPath: old.path)
        try recorder.started(processID: 222)
        try recorder.finish(exit: .init(status: 1, reason: .exit, processID: 222, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
        #expect(Set(recorder.record.evidence.map(\.name)) == ["latest.log", "crash-current.txt"])
        try "next game".write(to: latest, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: current)
        let copies = try recorder.record.evidence.map { try String(contentsOf: recorder.directory.appendingPathComponent($0.relativePath), encoding: .utf8) }.joined()
        #expect(copies.contains("current failure") && copies.contains("<redacted>"))
        #expect(!copies.contains("private-bearer") && !copies.contains("next game"))
    }
    @Test func redactionCoversQuotedArgumentsJSONAndURLs() {
        var redactor = GameLogRedactor(); redactor.addSecrets(["specific-secret"])
        let text = #"玩家 --accessToken "with spaces" --session=plain {"refresh_token":"json-secret"} https://example.test/?token=query-secret&ok=yes Authorization: Bearer bearer-secret specific-secret"#
        let redacted = redactor.redact(text)
        for secret in ["with spaces", "plain", "json-secret", "query-secret", "bearer-secret", "specific-secret"] { #expect(!redacted.contains(secret)) }
        #expect(redacted.contains("玩家") && redacted.contains("&ok=yes"))
    }
    @Test @MainActor func cancellationHistoryRejectsEscapingEvidenceAndReadsBoundedTail() throws {
        let (paths, instance) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.transition(.installation)
        for i in 0..<100 { try recorder.append("日志第 \(i) 行") }
        try recorder.fail(CancellationError(), cancelled: true)
        #expect(recorder.record.state == .cancelled && recorder.record.failure == nil)
        let tail = try GameSessionStore.logTail(paths: paths, session: recorder.record, byteLimit: 128)
        #expect(tail.contains("日志第 99 行") && !tail.contains("日志第 0 行") && !tail.contains("�"))
        let exported = paths.cache.appendingPathComponent("exported.log")
        try "previous export".write(to: exported, atomically: true, encoding: .utf8)
        try GameSessionStore.exportLog(paths: paths, session: recorder.record, to: exported)
        let full = try String(contentsOf: exported, encoding: .utf8)
        #expect(full.contains("日志第 0 行") && full.contains("日志第 99 行"))
        #expect(throws: (any Error).self) { try GameSessionStore.exportLog(paths: paths, session: recorder.record, to: recorder.directory.appendingPathComponent("session.json")) }
        var modified = recorder.record
        modified.evidence = [.init(relativePath: "reports/../../../outside.log", name: "outside", truncated: false)]
        try JSONEncoder().encode(modified).write(to: recorder.directory.appendingPathComponent("session.json"))
        #expect(throws: (any Error).self) { try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id) }
    }
}
