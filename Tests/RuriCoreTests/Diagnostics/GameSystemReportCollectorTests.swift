import Darwin
import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct GameSystemReportCollectorTests {
    private func ips(pid: Int32 = 123456, name: String = "ruri-game", detail: String = "native-failure") -> String {
        "{\"app_name\":\"\(name)\"}\n" +
        "{\"procName\":\"\(name)\",\"pid\":\(pid),\"exception\":{\"signal\":\"SIGBUS\"},\"detail\":\"\(detail)\"}\n"
    }
    private func write(_ text: String, name: String, root: URL, date: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(name)
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        return file
    }
    private func session() -> GameSession {
        var result = GameDiagnosisTests().session(status: SIGBUS, reason: .signal)
        let now = Date()
        result.exit = .init(status: SIGBUS, reason: .signal, processID: 123456, startedAt: now.addingTimeInterval(-30), endedAt: now, stopRequested: false)
        return result
    }

    @Test func matchingRequiresProcessTimeAndSafeCompleteFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = session()
        _ = try write(ips(), name: "matching.ips", root: root)
        _ = try write("Process: java [123456]\nException Type: EXC_BAD_ACCESS\n", name: "matching.crash", root: root)
        _ = try write(ips(pid: 123457), name: "other-pid.ips", root: root)
        _ = try write(ips(name: "another-app"), name: "other-app.ips", root: root)
        _ = try write(ips(), name: "old.ips", root: root, date: record.exit!.startedAt.addingTimeInterval(-1))
        _ = try write(ips(), name: "late.ips", root: root, date: record.exit!.endedAt.addingTimeInterval(121))
        _ = try write("{}\n{\"procName\":\"ruri-game\",\"pid\":123456,", name: "partial.ips", root: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.ips"), withDestinationURL: root.appendingPathComponent("matching.ips"))
        #expect(mkfifo(root.appendingPathComponent("pipe.ips").path, 0o600) == 0)
        var budget = 6 * 1_048_576
        let result = try GameSystemReportCollector.collect(session: record, budget: &budget, root: root)
        #expect(Set(result.documents.map(\.title)) == ["matching.ips", "matching.crash"])
        #expect(result.limitations.isEmpty)
    }

    @Test @MainActor func delayedReportIsPersistedAndSharedByViewerAndExportAfterOriginalDisappears() async throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let system = paths.root.appendingPathComponent("system")
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        recorder.addSecrets(["private-fixture-secret"])
        let exit = GameExit(status: SIGBUS, reason: .signal, processID: 123456, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false)
        try recorder.recordGameExit(exit)
        let content = ips(detail: "private-fixture-secret")
        let writer = Task {
            try await Task.sleep(for: .milliseconds(20))
            return try write(content, name: "ruri-game-delayed.ips", root: system)
        }
        await recorder.preserveEvidence(exit: exit, systemReportRoot: system, systemReportRetryDelays: [.milliseconds(10), .milliseconds(40), .milliseconds(100)])
        let original = try await writer.value
        try recorder.finish(exit: exit)
        let record = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        let evidence = try #require(record.evidence.first { $0.name == "ruri-game-delayed.ips" })
        let saved = recorder.directory.appendingPathComponent(evidence.relativePath)
        #expect(try FileManager.default.attributesOfItem(atPath: saved.path)[.posixPermissions] as? Int == 0o600)
        #expect(try String(contentsOf: original, encoding: .utf8) == content)
        try FileManager.default.removeItem(at: original)
        let reports = try GameEvidenceCollector.reports(paths: paths, session: record)
        let report = try #require(reports.first)
        #expect(reports.count == 1 && report.kind == .systemReport)
        #expect(report.text.contains("SIGBUS") && !report.text.contains("private-fixture-secret"))
        let collected = try GameEvidenceCollector.collect(paths: paths, session: record, includeGameLogs: true)
        #expect(collected.documents.filter { $0.kind == .systemReport }.count == 1)
        #expect(!collected.limitations.contains { $0.contains("macOS") })
        let bundle = try GameDiagnosticBundle.collect(paths: paths, session: record)
        let attachment = try #require(bundle.files.first { $0.id == report.id })
        let zip = paths.root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        try bundle.export(selectedIDs: [attachment.id], to: zip, paths: paths)
        let archive = try Archive(url: zip, accessMode: .read)
        var bytes = Data()
        _ = try archive.extract(try #require(archive[attachment.path])) { bytes.append($0) }
        #expect(String(decoding: bytes, as: UTF8.self) == GameShareRedactor().redact(report.text))
        var expired = record; expired.artifactState = .expired
        #expect(try GameEvidenceCollector.reports(paths: paths, session: expired).isEmpty)
    }

    @Test @MainActor func reportPickerIncludesSavedMinecraftAndJVMReportsWithoutOrdinaryLogs() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let game = paths.game(instance.id)
        _ = try write("minecraft-failure", name: "crash-current.txt", root: game.appendingPathComponent("crash-reports"))
        _ = try write("jvm-failure", name: "hs_err_pid123456.log", root: game)
        _ = try write("ordinary-output", name: "latest.log", root: game.appendingPathComponent("logs"))
        try recorder.finish(exit: .init(status: 1, reason: .exit, processID: 123456, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
        let before = try GameEvidenceCollector.reports(paths: paths, session: recorder.record)
        #expect(before.count == 2)
        try FileManager.default.removeItem(at: game.appendingPathComponent("crash-reports"))
        try FileManager.default.removeItem(at: game.appendingPathComponent("hs_err_pid123456.log"))
        let saved = try GameEvidenceCollector.reports(paths: paths, session: recorder.record)
        #expect(Set(saved.map(\.kind)) == [.gameReport, .jvmReport])
        #expect(Set(saved.map(\.title)) == ["crash-current.txt", "hs_err_pid123456.log"])
        #expect(saved.allSatisfy { !$0.text.contains("ordinary-output") && $0.relativePath != nil })
    }

    @Test func oversizedReportsAreBoundedAndMarkedAsExcerpts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "{}\n{\"procName\":\"ruri-game\",\"pid\":123456,\"frames\":[\n" +
            String(repeating: "\"native frame 日志\",\n", count: 150_000) + "\"end\"]}\n"
        _ = try write(content, name: "large.ips", root: root)
        var budget = 6 * 1_048_576
        let result = try GameSystemReportCollector.collect(session: session(), budget: &budget, root: root)
        let report = try #require(result.documents.first)
        #expect(report.truncated && report.text.utf8.count <= 2 * 1_048_576)
        #expect(report.text.contains("procName") && !report.text.contains("�"))
    }

    @Test func successfulAndRequestedExitsDoNotCollectSystemReports() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try write(ips(), name: "unrelated.ips", root: root)
        for stopped in [false, true] {
            var record = session()
            record.exit = .init(status: stopped ? SIGTERM : 0, reason: stopped ? .signal : .exit, processID: 123456,
                                startedAt: record.createdAt, endedAt: Date(), stopRequested: stopped)
            let result = try await GameSystemReportCollector.collectAfterExit(session: record, root: root)
            #expect(result.documents.isEmpty && result.limitations.isEmpty)
        }
    }

    @Test func incompleteReportCanBeCompletedDuringRetry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let record = session()
        _ = try write("{}\n{\"procName\":\"ruri-game\",\"pid\":123456,", name: "pending.ips", root: root)
        var budget = 6 * 1_048_576
        #expect(try GameSystemReportCollector.collect(session: record, budget: &budget, root: root).documents.isEmpty)
        let writer = Task.detached {
            try await Task.sleep(for: .milliseconds(20))
            _ = try write(ips(), name: "pending.ips", root: root)
        }
        defer { writer.cancel() }
        let result = try await GameSystemReportCollector.collectAfterExit(session: record, root: root, retryDelays: [.milliseconds(10), .milliseconds(40), .seconds(1)])
        try await writer.value
        #expect(result.documents.first?.text.contains("native-failure") == true)
    }
}
