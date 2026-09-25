import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct GameDiagnosticBundleTests {
    @Test func shareRedactionHandlesQuotedCredentialsPathsAndCustomContent() {
        let text = """
        {"apiKey":"api key with spaces", "id_token":"private-id", "username":"PlayerName"}
        --accessToken "secret token" --username MyPlayer --token command-token
        Authorization: Basic private-basic
        Cookie: private-cookie; another=value
        /Users/Example User/private/config.txt /Users/somebody/game/log.txt
        name@example.test 127.0.0.1 [2001:db8::1] https://private.server.test/path?token=url-token
        Connecting to secret-server.test, 25565
        4b8fffa6-7cc0-40a8-ab00-00c8f9d40390 custom-private-chat
        """
        let result = GameShareRedactor(additionalPrivateText: ["custom-private-chat"], homeDirectory: "/Users/Example User").redact(text)
        for secret in ["api key with spaces", "private-id", "PlayerName", "secret token", "MyPlayer", "command-token", "private-basic", "private-cookie", "Example User", "somebody", "name@example.test", "127.0.0.1", "2001:db8::1", "private.server.test", "url-token", "secret-server.test", "4b8fffa6-7cc0-40a8-ab00-00c8f9d40390", "custom-private-chat"] {
            #expect(!result.contains(secret), "Leaked fixture: \(secret)")
        }
        #expect(result.contains("config.txt") && result.contains("25565"))
    }
    @Test func incompleteQuotedCredentialsAndPlainPlayerNamesAreMasked() {
        for text in [#"--accessToken "first private remainder"#, #"{"apiKey":"first private remainder"#, #"--session 'first private remainder"#] {
            let redacted = GameShareRedactor().redact(text)
            #expect(!redacted.contains("first") && !redacted.contains("private") && !redacted.contains("remainder"))
        }
        let persisted = GameLogRedactor().redact(#"--accessToken "first private remainder"#)
        #expect(!persisted.contains("remainder"))
        let name = GameShareRedactor().redact("[Render thread/INFO] Setting user: PrivatePlayer\nNext log line")
        #expect(!name.contains("PrivatePlayer") && name.contains("Next log line"))
    }
    @Test @MainActor func archiveContainsExactlySelectedPreviewBytesAndProtectsSources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root.appendingPathComponent("data")); try paths.prepare()
        let recorder = try GameSessionRecorder(paths: paths, instance: GameInstance(name: "private-title", gameVersion: "1.21.1"), accountMode: "offline")
        try recorder.append("Error: Could not find or load main class PRIVATE-EVIDENCE")
        try recorder.fail(RuriError.message("failed"), cancelled: false)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record)
        let preview = try GameDiagnosticBundle.preview(session: recorder.record, diagnosis: diagnosis, homeDirectory: root.path)
        try GameSessionEventStore.append("new unreviewed secret", sessionID: recorder.record.id, paths: paths)
        let zip = root.appendingPathComponent("report.zip")
        let ids: Set<String> = ["summary", "launcher.log"]
        try preview.export(selectedIDs: ids, to: zip, paths: paths)
        let archive = try Archive(url: zip, accessMode: .read)
        #expect(Set(archive.map(\.path)) == Set(preview.files.filter { ids.contains($0.id) }.map(\.path)))
        for file in preview.files where ids.contains(file.id) {
            let entry = try #require(archive[file.path]); var actual = Data()
            _ = try archive.extract(entry) { actual.append($0) }
            #expect(actual == Data(file.text.utf8))
            #expect(!file.text.contains("new unreviewed secret"))
        }
        try preview.export(selectedIDs: ["summary"], to: zip, paths: paths)
        let summaryOnly = try Archive(url: zip, accessMode: .read)
        #expect(summaryOnly.map(\.path) == ["diagnosis.txt"])
        var summaryData = Data(); _ = try summaryOnly.extract(try #require(summaryOnly["diagnosis.txt"])) { summaryData.append($0) }
        #expect(!String(decoding: summaryData, as: UTF8.self).contains("PRIVATE-EVIDENCE"))
        #expect(throws: (any Error).self) { try preview.export(selectedIDs: [], to: zip, paths: paths) }
        #expect(throws: (any Error).self) { try preview.export(selectedIDs: ["../accounts.json"], to: zip, paths: paths) }
        #expect(throws: (any Error).self) { try preview.export(selectedIDs: ids, to: paths.root.appendingPathComponent("report.zip"), paths: paths) }
        #expect(try GameSessionEventStore.entries(paths: paths, sessionID: recorder.record.id).contains { $0.text == "new unreviewed secret" })
    }
}
