import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

struct CacheCommandTests {
    @MainActor @Test func cleanPreviewKeepsFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = root.appendingPathComponent("cache/pack-1.mrpack")
        try FileManager.default.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 4096).write(to: archive)
        // A fresh file may belong to another process's import, so even a clean keeps it.
        for arguments in [["cache", "status"], ["cache", "clean", "--dry-run"], ["cache", "clean"]] {
            let output = CommandCapture()
            #expect(await CLIApplication.run(["--data-dir", root.path] + arguments + ["--json"], write: output.write) == 0)
            #expect(try output.value["data"]["bytes"] == .integer(0))
        }
        #expect(FileManager.default.fileExists(atPath: archive.path))
    }
}
