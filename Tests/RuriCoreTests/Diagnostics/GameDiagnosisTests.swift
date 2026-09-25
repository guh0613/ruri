import Foundation
import Testing
@testable import RuriCore

struct GameDiagnosisTests {
    func session(state: GameSession.State = .failed, status: Int32 = 1, reason: GameExit.Reason = .exit, stopRequested: Bool = false) -> GameSession {
        let now = Date()
        return .init(id: UUID(), instanceID: UUID(), instanceName: "诊断测试", gameVersion: "1.21.1", loader: "fabric", loaderVersion: nil, memoryMB: 4096,
                     operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 123,
                     createdAt: now, updatedAt: now, state: state, stage: .finished,
                     exit: .init(status: status, reason: reason, processID: 123, startedAt: now, endedAt: now, stopRequested: stopRequested), events: [], evidence: [])
    }
    func document(_ text: String, kind: GameDiagnosticDocument.Kind = .output, id: String = "launcher.log") -> GameDiagnosticDocument {
        .init(id: id, relativePath: id, title: id, kind: kind, text: text)
    }
    @Test func requestedStopAndSuccessDoNotTurnModWarningsIntoCrashes() throws {
        let lines = document("[12:00:00] [main/ERROR]: Mixin apply failed Controlify\nIncompatible mods found!")
        for record in [session(state: .stopped, status: 143, stopRequested: true), session(state: .succeeded, status: 0), session(state: .cancelled)] {
            let diagnosis = try GameDiagnosticAnalyzer.analyze(session: record, documents: [lines])
            #expect(diagnosis.findings.isEmpty)
        }
    }
    @Test func signalDoesNotClaimSystemMemoryOrModIncompatibility() throws {
        let record = session(status: 9, reason: .signal)
        let diagnosis = try GameDiagnosticAnalyzer.analyze(session: record, documents: [document("[12:00:00] [main/ERROR]: java.lang.OutOfMemoryError\nIncompatible mods found!")])
        #expect(diagnosis.findings.isEmpty)
    }
    @Test func warningsAndAuthenticationErrorsDoNotIdentifyACulprit() throws {
        let log = """
        [12:00:00] [main/WARN]: Mixin apply failed mod.example
        Caused by: java.lang.OutOfMemoryError
        [12:00:01] [Render thread/ERROR]: Failed to fetch profile: authentication 401
        java.lang.Exception: offline account
        [12:00:02] [main/INFO]: Warnings were found!
        Incompatible mods found!
        """
        for variant in [log, log.replacingOccurrences(of: #"\[12:00:0[0-2]\] "#, with: "", options: .regularExpression)] {
            #expect(try GameDiagnosticAnalyzer.analyze(session: session(), documents: [document(variant)]).findings.isEmpty)
        }
    }
    @Test func dependenciesIncludeTheirVersionEvidenceAndPrecedeMixinClues() throws {
        let log = """
        [12:00:00] [main/ERROR]: Mixin apply failed target
        [12:00:01] [main/ERROR]: Incompatible mods found!
        Mod 'Example' (example) 2.0 requires version 0.116 or later of fabric-api, which is missing!
        A potential solution has been determined: Install fabric-api.
        """
        let diagnosis = try GameDiagnosticAnalyzer.analyze(session: session(), documents: [document(log.replacingOccurrences(of: "\n", with: "\r\n"))])
        #expect(diagnosis.findings.map(\.id) == ["dependencies", "mixin"])
        let first = try #require(diagnosis.findings.first)
        #expect(first.evidence.first?.line == 2)
        #expect(first.evidence.first?.excerpt.contains("0.116") == true)
        #expect(first.confidence == .reported)
        #expect(diagnosis.findings.last?.confidence == .possible)
    }
    @Test func reportStackIsEvidenceButModInventoryIsNot() throws {
        let text = """
        ---- Minecraft Crash Report ----
        Description: Initializing game
        java.lang.RuntimeException: Could not execute entrypoint stage 'client' due to errors, provided by 'example'!
        Caused by: java.lang.OutOfMemoryError: Java heap space
        A detailed walkthrough of the error, its code path and all known details is as follows:
        Mod inventory: found duplicate mods: just a misleading name
        """
        let diagnosis = try GameDiagnosticAnalyzer.analyze(session: session(), documents: [document(text, kind: .gameReport)])
        #expect(diagnosis.findings.map(\.id) == ["mod-entrypoint", "heap-memory"])
    }
    @Test func repeatedCopiesAreGroupedAndPreparatoryErrorsKeepTheirStage() throws {
        let log = "错误: 找不到或无法加载主类 example.Missing\n原因: java.lang.ClassNotFoundException: example.Missing"
        let result = try GameDiagnosticAnalyzer.analyze(session: session(), documents: [document(log), document(log, id: "reports/0-latest.log")])
        #expect(result.findings.count == 1 && result.findings[0].evidence.count == 2)
        var record = session(); record.exit = nil; record.stage = .account; record.failure = "Refresh request failed"
        let preparation = try GameDiagnosticAnalyzer.analyze(session: record, documents: [])
        #expect(preparation.findings.first?.actions.contains(.accounts) == true)
    }
    @Test func activeOrUnknownExitDoesNotInventADiagnosis() throws {
        var record = session(state: .running); record.exit = nil
        let result = try GameDiagnosticAnalyzer.analyze(session: record, documents: [document("Incompatible mods found!")])
        #expect(result.findings.isEmpty)
    }
    @Test @MainActor func loaderUsesOnlySnapshotEvidenceAndBoundsLargeLogs() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let instance = GameInstance(name: "诊断", gameVersion: "1.21.1")
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        try recorder.fail(RuriError.message("failed"), cancelled: false)
        try FileManager.default.createDirectory(at: recorder.directory, withIntermediateDirectories: true)
        let url = recorder.directory.appendingPathComponent("console.log")
        let large = String(repeating: "日志内容无需分析\n", count: 230_000) + "Error: Could not find or load main class example.Missing\n"
        try large.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: paths.game(instance.id).appendingPathComponent("logs"), withIntermediateDirectories: true)
        try "Incompatible mods found!".write(to: paths.game(instance.id).appendingPathComponent("logs/latest.log"), atomically: true, encoding: .utf8)
        let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record)
        #expect(diagnosis.findings.map(\.id) == ["main-class"])
        #expect(diagnosis.documents.contains { $0.isTail && !$0.text.contains("�") })
        #expect(!diagnosis.limitations.isEmpty)
        #expect(diagnosis.documents.reduce(0) { $0 + $1.text.utf8.count } <= 4_194_400)
        #expect(try String(contentsOf: url, encoding: .utf8) == large)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: paths.game(instance.id).appendingPathComponent("logs/latest.log"))
        let unsafe = try GameDiagnosticAnalyzer.load(paths: paths, session: recorder.record)
        #expect(!unsafe.findings.contains { $0.id == "dependencies" })
        #expect(!unsafe.limitations.isEmpty)
    }
}
