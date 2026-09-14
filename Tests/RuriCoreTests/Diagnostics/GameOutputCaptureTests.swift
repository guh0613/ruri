import Foundation
import Testing
@testable import RuriCore

struct GameOutputCaptureTests {
    @Test func tailStaysWithinByteBudgetAcrossWrapsAndHugeLines() {
        var tail = GameOutputTail(capacity: 17)
        tail.append(Data("first\nsecond\n".utf8))
        #expect(String(decoding: tail.snapshot(final: true), as: UTF8.self) == "first\nsecond\n")
        tail.append(Data("third\nlast".utf8))
        #expect(tail.count == 17 && tail.truncated)
        #expect(String(decoding: tail.snapshot(final: true), as: UTF8.self) == "third\nlast")
        #expect(String(decoding: tail.snapshot(final: false), as: UTF8.self) == "third\n")
        tail.append(Data(repeating: 65, count: 1_000_000))
        #expect(tail.count == 17 && tail.snapshot(final: true).isEmpty)
        tail.append(Data("\nready\n".utf8))
        #expect(String(decoding: tail.snapshot(final: true), as: UTF8.self) == "ready\n")
    }

    @Test func quietCaptureDoesNotFormatUntilRequestedAndRedactsSplitCredentials() throws {
        var redactor = GameLogRedactor(); redactor.addSecrets(["private-token"])
        let capture = try GameOutputCapture(redactor: redactor)
        capture.receive(Data("玩家 private-".utf8))
        #expect(capture.snapshot().isEmpty)
        capture.receive(Data("token\nAuthorization: Bearer abcdef\n".utf8))
        let preview = capture.snapshot()
        #expect(preview.contains("玩家 <redacted>") && !preview.contains("abcdef"))
        capture.receive(Data("last private-token".utf8)); capture.finish()
        #expect(capture.snapshot(final: true).contains("last <redacted>"))
    }

    @Test func debugCaptureBatchesCompleteLinesAndDropsOversizedLinesWithoutFragments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("debug.log"); try Data().write(to: file)
        var redactor = GameLogRedactor(); redactor.addSecrets(["private-token"])
        let capture = try GameOutputCapture(redactor: redactor, debugLogURL: file)
        capture.receive(Data("中文 private-".utf8))
        #expect(try Data(contentsOf: file).isEmpty)
        capture.receive(Data("token\n".utf8))
        capture.receive(Data(repeating: 120, count: 300_000))
        capture.receive(Data("private-token\nlast private-token".utf8)); capture.finish()
        let log = try String(contentsOf: file, encoding: .utf8)
        #expect(log.contains("中文 <redacted>") && log.contains("last <redacted>"))
        #expect(!log.contains("private-token") && !log.contains("xxxx") && capture.writeFailure == nil)
    }

    @Test func debugDiskBudgetStopsWritingButKeepsTheFailureTail() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let capture = try GameOutputCapture(redactor: .init(), debugLogURL: file, debugByteLimit: 32)
        capture.receive(Data("first\n".utf8))
        capture.receive(Data((String(repeating: "x", count: 100) + "\n").utf8))
        capture.receive(Data("final failure\n".utf8)); capture.finish()
        #expect(try Data(contentsOf: file).count <= 32)
        #expect(capture.writeFailure != nil && capture.snapshot(final: true).contains("final failure"))
    }

    @Test func debugDecodesXMLAndUTF8AcrossArbitraryByteBoundaries() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        var redactor = GameLogRedactor(); redactor.addSecrets(["private-token"])
        let capture = try GameOutputCapture(redactor: redactor, debugLogURL: file)
        let text = "<log4j:Event level=\"ERROR\" thread=\"Render thread\">\n<log4j:Message><![CDATA[中文 private-token]]></log4j:Message>\n</log4j:Event>\n"
        for byte in text.utf8 { capture.receive(Data([byte])) }
        capture.finish()
        #expect(try String(contentsOf: file, encoding: .utf8) == "[Render thread/ERROR] 中文 <redacted>\n")
    }
}
