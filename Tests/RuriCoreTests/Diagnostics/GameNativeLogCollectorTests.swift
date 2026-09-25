import Darwin
import Foundation
import Testing
@testable import RuriCore

struct GameNativeLogCollectorTests {
    private func write(_ text: String, _ relative: String, game: URL, date: Date? = nil) throws -> URL {
        let url = game.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }

    @MainActor private func finish(_ recorder: GameSessionRecorder, status: Int32 = 0) throws {
        try recorder.finish(exit: .init(status: status, reason: .exit, processID: 123456,
                                       startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
    }

    @Test @MainActor func nativeLogsAreCollectedOnlyOnRequestWithoutChangingSources() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let game = paths.game(instance.id)
        let content = "Authorization: Bearer private-token\n游戏已启动\n"
        let latest = try write(content, "logs/latest.log", game: game)
        _ = try write("Loader debug detail\n", "logs/debug.log", game: game)
        _ = try write("private options", "options.txt", game: game)
        try finish(recorder)
        let saved = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record)
        #expect(saved.documents.allSatisfy { $0.gameRelativePath == nil })
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        #expect(Set(diagnosis.documents.compactMap(\.gameRelativePath)) == ["logs/latest.log", "logs/debug.log"])
        #expect(try String(contentsOf: latest, encoding: .utf8) == content)
        let text = try #require(diagnosis.documents.first { $0.gameRelativePath == "logs/latest.log" }).text
        #expect(text.contains("游戏已启动") && !text.contains("private-token"))
    }

    @Test @MainActor func onlyReportsFromThisRunAndExactJVMPIDAreIncluded() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let game = paths.game(instance.id), old = recorder.record.createdAt.addingTimeInterval(-60)
        _ = try write("current game output", "logs/latest.log", game: game)
        _ = try write("stale debug output", "logs/debug.log", game: game, date: old)
        _ = try write("current crash", "crash-reports/crash-current.txt", game: game)
        _ = try write("previous crash", "crash-reports/crash-old.txt", game: game, date: old)
        _ = try write("current JVM", "hs_err_pid123456.log", game: game)
        _ = try write("another JVM", "hs_err_pid123457.log", game: game)
        try finish(recorder)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        #expect(Set(diagnosis.documents.compactMap(\.gameRelativePath)) == ["logs/latest.log", "crash-reports/crash-current.txt", "hs_err_pid123456.log"])
    }

    @Test @MainActor func currentNativeFileReplacesTheSavedDuplicate() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        _ = try write("Incompatible mods found!\n", "logs/latest.log", game: paths.game(instance.id))
        try finish(recorder, status: 1)
        #expect(recorder.record.evidence.contains { $0.name == "latest.log" })
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        #expect(diagnosis.documents.filter { $0.title.contains("latest.log") }.count == 1)
        #expect(diagnosis.findings.contains { $0.id == "dependencies" })
    }

    @Test @MainActor func nextRunCannotReplaceHistoricalEvidenceEvenInsideTimestampTolerance() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let first = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        _ = try write("first-run-evidence", "logs/latest.log", game: paths.game(instance.id))
        try finish(first, status: 1)
        let second = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try second.started(processID: 123456)
        _ = try write("second-run-evidence", "logs/latest.log", game: paths.game(instance.id), date: first.record.exit!.endedAt)
        try finish(second)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: first.record, includeGameLogs: true)
        #expect(diagnosis.documents.allSatisfy { $0.gameRelativePath == nil && !$0.text.contains("second-run-evidence") })
        #expect(diagnosis.documents.contains { $0.text.contains("first-run-evidence") })
        #expect(!diagnosis.limitations.isEmpty)
    }

    @Test(arguments: [GameRunDirectory.shared, .custom]) @MainActor
    func laterRunsInAnotherInstanceSharingTheDirectoryAreDetected(mode: GameRunDirectory) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = LauncherPaths(root: root.appendingPathComponent("data"))
        var firstInstance = GameInstance(name: "First", gameVersion: "1.21.1"); firstInstance.runDirectory = mode
        var secondInstance = GameInstance(name: "Second", gameVersion: "1.21.1"); secondInstance.runDirectory = mode
        if mode == .custom {
            let game = root.appendingPathComponent("external-game")
            try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
            let custom = try CustomRunDirectory.register(at: game, paths: base)
            firstInstance.customRunDirectory = custom; secondInstance.customRunDirectory = custom
        }
        var state = PersistentState(); state.instances = [firstInstance, secondInstance]
        let paths = base.configured(with: try StateStore.save(state, to: base))
        let first = try GameSessionRecorder(paths: paths, instance: firstInstance, accountMode: "offline")
        _ = try write("first-output", "logs/latest.log", game: paths.game(firstInstance.id))
        try finish(first)
        let current = try GameDiagnosticAnalyzer.load(paths: paths, session: first.record, includeGameLogs: true)
        #expect(current.documents.contains { $0.gameRelativePath == "logs/latest.log" && $0.text == "first-output" })
        let second = try GameSessionRecorder(paths: paths, instance: secondInstance, accountMode: "offline")
        try second.started(processID: 123456)
        _ = try write("other-instance-output", "logs/latest.log", game: paths.game(secondInstance.id), date: first.record.exit!.endedAt)
        try finish(second)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: first.record, includeGameLogs: true)
        #expect(diagnosis.documents.allSatisfy { $0.gameRelativePath == nil })
        #expect(!diagnosis.limitations.isEmpty)
    }

    @Test @MainActor func preparationFailureDoesNotCollectPreviousGameOutput() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        _ = try write("previous-output", "logs/latest.log", game: paths.game(instance.id))
        try recorder.fail(RuriError.message("preparation failed"), cancelled: false)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        #expect(diagnosis.documents.allSatisfy { $0.gameRelativePath == nil })
        #expect(!diagnosis.limitations.isEmpty)
    }

    @Test @MainActor func symlinksAndNamedPipesAreSkippedWithoutReadingTheirTargets() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let game = paths.game(instance.id), logs = game.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let secret = try write("outside-private-content", "secret.txt", game: paths.root)
        try FileManager.default.createSymbolicLink(at: logs.appendingPathComponent("latest.log"), withDestinationURL: secret)
        #expect(mkfifo(logs.appendingPathComponent("debug.log").path, 0o600) == 0)
        try FileManager.default.createDirectory(at: game.appendingPathComponent("crash-reports"), withIntermediateDirectories: true)
        for relative in ["crash-reports/crash-link.txt", "hs_err_pid123456.log"] {
            try FileManager.default.createSymbolicLink(at: game.appendingPathComponent(relative), withDestinationURL: secret)
        }
        try finish(recorder)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        #expect(diagnosis.documents.allSatisfy { $0.gameRelativePath == nil && !$0.text.contains("outside-private-content") })
        try FileManager.default.removeItem(at: logs)
        try FileManager.default.createSymbolicLink(at: logs, withDestinationURL: paths.root)
        _ = try write("outside-private-content", "latest.log", game: paths.root)
        let linkedDirectory = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        #expect(linkedDirectory.documents.allSatisfy { $0.gameRelativePath == nil })
    }

    @Test @MainActor func largeNativeLogsKeepBoundedUTF8HeadsAndTails() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let content = "start-marker\n" + String(repeating: "日志内容🐈\n", count: 620_000) + "end-marker\n"
        for name in ["latest.log", "debug.log"] { _ = try write(content, "logs/" + name, game: paths.game(instance.id)) }
        try finish(recorder)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record, includeGameLogs: true)
        let native = diagnosis.documents.filter { $0.gameRelativePath != nil }
        #expect(native.count == 4 && native.allSatisfy { $0.truncated && !$0.text.contains("�") })
        #expect(native.filter { $0.isTail }.allSatisfy { $0.text.contains("end-marker") && !$0.text.contains("start-marker") })
        #expect(native.filter { !$0.isTail }.allSatisfy { $0.text.contains("start-marker") && !$0.text.contains("end-marker") })
        #expect(native.reduce(0) { $0 + $1.text.utf8.count } <= 12 * 1_048_576)
        #expect(native.filter { $0.gameRelativePath == "logs/latest.log" }.reduce(0) { $0 + $1.text.utf8.count } <= 8 * 1_048_576)
    }
}
