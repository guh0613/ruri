import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

final class CommandCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data(), stderr = Data()
    func write(_ data: Data, _ error: Bool) { lock.withLock { if error { stderr.append(data) } else { stdout.append(data) } } }
    var output: Data { lock.withLock { stdout } }
    var errors: Data { lock.withLock { stderr } }
    var value: OperationValue { get throws { try JSONDecoder().decode(OperationValue.self, from: output) } }
}

struct CommandContractTests {
    @MainActor @Test func schemaDoesNotLoadCorruptState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("broken".utf8).write(to: root.appendingPathComponent("state.json"))
        let output = CommandCapture()
        let status = await CLIApplication.run(["--data-dir", root.path, "schema", "cli", "install", "--json"], write: output.write)
        #expect(status == 0)
        #expect(try output.value["ok"] == .bool(true))
        #expect(output.errors.isEmpty)
        #expect(try String(contentsOf: root.appendingPathComponent("state.json"), encoding: .utf8) == "broken")
    }
    @MainActor @Test func invalidCommandHasStructuredFailure() async throws {
        let output = CommandCapture()
        let status = await CLIApplication.run(["unknown-command", "--json"], write: output.write)
        #expect(status == 2)
        #expect(try output.value["error"]["code"] == .string("INVALID_ARGUMENT"))
    }
    @MainActor @Test func ndjsonHasOneFinalResult() async throws {
        let output = CommandCapture()
        #expect(await CLIApplication.run(["app", "info", "--output", "ndjson"], write: output.write) == 0)
        let lines = String(decoding: output.output, as: UTF8.self).split(separator: "\n")
        #expect(lines.count == 1)
        let event = try JSONDecoder().decode(OperationValue.self, from: Data(lines[0].utf8))
        #expect(event["type"] == .string("result"))
        #expect(event["data"]["ok"] == .bool(true))
    }
    @Test func installerPreservesUnownedFilesAndRepairsOwnedLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let binary = root.appendingPathComponent("ruri-cli")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let service = try CLIInstallation(executable: binary, binDirectory: root.appendingPathComponent("bin"))
        _ = try service.install(dryRun: true)
        #expect(!FileManager.default.fileExists(atPath: service.binDirectory.path))
        _ = try service.install()
        #expect(try service.install()["changed"] == .bool(false))
        _ = try service.uninstall()
        try Data("user file".utf8).write(to: service.link)
        #expect(throws: OperationFailure.self) { try service.install() }
        #expect(throws: OperationFailure.self) { try service.uninstall() }
        #expect(try String(contentsOf: service.link, encoding: .utf8) == "user file")
    }
}
