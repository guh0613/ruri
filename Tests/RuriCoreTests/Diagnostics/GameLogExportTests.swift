import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct GameLogExportTests {
    @Test @MainActor func completeExportContainsTheMiddleAndNeverReopensTheLiveLog() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root.appendingPathComponent("data")); try paths.prepare()
        let instance = GameInstance(name: "Full export", gameVersion: "fixture")
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let logs = paths.game(instance.id).appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("latest.log")
        let padding = String(repeating: "ordinary " + String(repeating: "x", count: 4080) + "\n", count: 1150)
        let content = "start-marker\nAuthorization: Bearer source-private-token\n" + padding + "middle-marker private-middle-text\n" + padding + "end-marker\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
        try recorder.finish(exit: .init(status: 0, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
        let record = recorder.record
        let bundle = try await Task.detached(priority: .utility) { try GameDiagnosticBundle.collect(paths: paths, session: record) }.value
        let attachment = try #require(bundle.files.first { $0.path == "game/logs/latest.log" })
        #expect(attachment.previewTruncated && attachment.text.utf8.count < 140_000)
        #expect(!attachment.text.contains("middle-marker") && attachment.byteCount > 8 * 1_048_576)
        let redacted = try await Task.detached(priority: .utility) { try bundle.redacting(["private-middle-text"]) }.value
        try "new unreviewed private output".write(to: file, atomically: true, encoding: .utf8)
        let destination = root.appendingPathComponent("full.zip")
        try await Task.detached(priority: .utility) { try redacted.export(selectedIDs: [attachment.id], to: destination, paths: paths) }.value
        let archive = try Archive(url: destination, accessMode: .read)
        let entry = try #require(archive[attachment.path]); var bytes = Data()
        _ = try archive.extract(entry) { bytes.append($0) }
        let exported = String(decoding: bytes, as: UTF8.self)
        #expect(exported.contains("start-marker") && exported.contains("middle-marker") && exported.contains("end-marker"))
        #expect(!exported.contains("private-middle-text") && !exported.contains("source-private-token") && !exported.contains("unreviewed"))
        #expect(bytes.count == redacted.files.first { $0.id == attachment.id }?.byteCount)
    }

    @Test @MainActor func nativeCursorSwitchesFilesAndNeverShowsAPreviousUnchangedLog() async throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let logs = paths.game(instance.id).appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let file = logs.appendingPathComponent("latest.log")
        try "previous-output\n".write(to: file, atomically: true, encoding: .utf8)
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        recorder.prepareGame(directory: paths.game(instance.id))
        try recorder.started(processID: ProcessInfo.processInfo.processIdentifier)
        let cursor = try GameSessionLogCursor(paths: paths, session: recorder.record, source: .console)
        _ = try await cursor.refresh()
        #expect(await cursor.preview.text.isEmpty)
        try "first-current\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await cursor.refresh())
        #expect(await cursor.preview.text == "first-current\n")
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("appended-current\n".utf8)); try handle.close()
        #expect(try await cursor.refresh())
        #expect(try await !cursor.refresh())
        let text = await cursor.preview.text
        #expect(text.contains("first-current") && text.contains("appended-current") && !text.contains("previous-output"))
        try "rotated-current\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await cursor.refresh())
        #expect(await cursor.preview.text == "rotated-current\n")
        try recorder.close()
    }

    @Test @MainActor func anUnsafeLongLineIsReportedInsteadOfClaimingACompleteExport() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let logs = paths.game(instance.id).appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data(repeating: 120, count: 1_048_577).write(to: logs.appendingPathComponent("latest.log"))
        try recorder.finish(exit: .init(status: 0, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
        let bundle = try GameDiagnosticBundle.collect(paths: paths, session: recorder.record)
        #expect(bundle.files.contains { $0.id.hasPrefix("unavailable/") })
        #expect(!bundle.files.contains { $0.snapshot != nil })
    }
    @Test @MainActor func streamingRedactionMasksQuotedCredentialContinuations() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let logs = paths.game(instance.id).appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let content = #"{"access_token":"first'private"# + "\n" + #"second\"private"# + "\n" + #"third-private","next":"safe"}"# + "\n"
        try content.write(to: logs.appendingPathComponent("latest.log"), atomically: true, encoding: .utf8)
        try recorder.finish(exit: .init(status: 0, reason: .exit, processID: 123, startedAt: recorder.record.createdAt, endedAt: Date(), stopRequested: false))
        let source = try #require(try GameLogSources.native(paths: paths, session: recorder.record).first)
        let snapshot = try GameLogSnapshot.capture(source, redactor: GameShareRedactor())
        #expect(!snapshot.preview.contains("first") && !snapshot.preview.contains("second") && !snapshot.preview.contains("third-private"))
        #expect(snapshot.preview.contains("safe"))
    }

}
