import RuriLocalization
import Foundation

public struct GameDiagnosticDocument: Identifiable, Sendable {
    public enum Kind: String, Sendable { case preparation, output, gameReport, jvmReport }
    public let id: String
    public let relativePath: String?
    public let title: String
    public let kind: Kind
    public let text: String
    public var isTail = false
    public var truncated = false
}

public struct GameDiagnosis: Sendable {
    public struct Evidence: Identifiable, Sendable {
        public let documentID: String
        public let line: Int
        public let excerpt: String
        public var id: String { "\(documentID):\(line)" }
    }
    public enum Action: String, CaseIterable, Sendable {
        case settings, mods, accounts, repair, files, collect
        public var title: String {
            switch self {
            case .settings: Messages.CoreGameDiagnosis.titleText1.localized
            case .mods: Messages.CoreGameDiagnosis.titleText2.localized
            case .accounts: Messages.CoreGameDiagnosis.titleText3.localized
            case .repair: Messages.CoreGameDiagnosis.titleText4.localized
            case .files: Messages.CoreGameDiagnosis.titleText5.localized
            case .collect: Messages.CoreGameDiagnosis.titleText6.localized
            }
        }
    }
    public struct Finding: Identifiable, Sendable {
        public enum Confidence: String, Sendable {
            case reported, possible
            public var title: String { switch self { case .reported: Messages.CoreGameDiagnosis.titleText7.localized; case .possible: Messages.CoreGameDiagnosis.titleText8.localized } }
        }
        public let id: String
        public let title: String
        public let explanation: String
        public let confidence: Confidence
        public let steps: [String]
        public let actions: [Action]
        public var evidence: [Evidence]
    }
    public let sessionID: UUID
    public let title: String
    public let summary: String
    public let facts: [String]
    public let findings: [Finding]
    public let documents: [GameDiagnosticDocument]
    public let limitations: [String]
}

/// Rules describe what a source actually reports, not which mod is guilty.
/// Only this session's saved evidence is read; log text never supplies a path.
public enum GameDiagnosticAnalyzer {
    public static func load(paths: LauncherPaths, session: GameSession) throws -> GameDiagnosis {
        var documents: [GameDiagnosticDocument] = [], limitations: [String] = []
        let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
        if let failure = session.displayFailure {
            documents.append(.init(id: "preparation", relativePath: nil, title: session.stage.title, kind: .preparation, text: failure))
        }
        var budget = 12 * 1_048_576 // Reserve 4 MiB for the session's own output.
        func read(_ relative: String, title: String, kind: GameDiagnosticDocument.Kind, truncated: Bool = false) throws {
            try Task.checkCancellation()
            let url = try LauncherPaths.safePath(relative, within: directory)
            let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw RuriError.message(Messages.CoreGameDiagnosis.attributesText1) }
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let size = try handle.seekToEnd(); try handle.seek(toOffset: 0)
            let count = min(budget, 2 * 1_048_576)
            guard count > 0 else { limitations.append(Messages.CoreGameDiagnosis.countText1(String(describing: title)).localized); return }
            let head = try handle.read(upToCount: count) ?? Data(); budget -= head.count
            let partial = size > head.count
            var text = String(decoding: head, as: UTF8.self)
            if partial, let end = text.lastIndex(of: "\n") { text = String(text[..<end]) }
            documents.append(.init(id: relative, relativePath: relative, title: title, kind: kind, text: text, truncated: truncated || partial))
            if partial && kind == .output && budget > 0 {
                let tailCount = min(budget, count)
                try handle.seek(toOffset: max(UInt64(head.count), size - UInt64(tailCount)))
                let tail = try handle.read(upToCount: tailCount) ?? Data(); budget -= tail.count
                let tailText = String(decoding: tail, as: UTF8.self)
                // A tail starts at an arbitrary byte. Discard the incomplete first line.
                documents.append(.init(id: relative + "#tail", relativePath: relative, title: Messages.CoreGameDiagnosis.tailTitle(title).localized, kind: kind,
                                       text: String(tailText.drop(while: { $0 != "\n" }).dropFirst()), isTail: true, truncated: true))
            }
            if truncated || partial { limitations.append(Messages.CoreGameDiagnosis.tailTextText2(String(describing: title)).localized) }
        }
        // Prioritize a crash report over duplicate copies of standard output.
        let reports = session.evidence.sorted { ($0.name == "latest.log" ? 1 : 0, $0.name) < ($1.name == "latest.log" ? 1 : 0, $1.name) }
        for item in reports.prefix(12) {
            guard item.relativePath.hasPrefix("reports/") else { limitations.append(Messages.CoreGameDiagnosis.reportsText1.localized); continue }
            let kind: GameDiagnosticDocument.Kind = item.name.hasPrefix("hs_err_pid") ? .jvmReport : item.name.hasPrefix("crash-") ? .gameReport : .output
            do { try read(item.relativePath, title: item.name, kind: kind, truncated: item.truncated) }
            catch is CancellationError { throw CancellationError() }
            catch { limitations.append(Messages.CoreGameDiagnosis.kindText1(String(describing: item.name), String(describing: error.localizedDescription)).localized) }
        }
        if reports.count > 12 { limitations.append(Messages.CoreGameDiagnosis.kindText2(Int64(reports.count)).localized) }
        budget += 4 * 1_048_576
        do { try read("launcher.log", title: "launcher.log", kind: .output) }
        catch is CancellationError { throw CancellationError() }
        catch { limitations.append(Messages.CoreGameDiagnosis.kindText3(String(describing: error.localizedDescription)).localized) }
        return try analyze(session: session, documents: documents, limitations: limitations)
    }

    public static func analyze(session: GameSession, documents: [GameDiagnosticDocument], limitations: [String] = []) throws -> GameDiagnosis {
        var facts = [Messages.CoreGameDiagnosis.factsText1(String(describing: session.stage.title)).localized, "Minecraft \(session.gameVersion) · \(session.loader) \(session.loaderVersion ?? "")",
                     Messages.CoreGameDiagnosis.factsText3(String(describing: session.java ?? Messages.CoreGameDiagnosis.factsText2.localized), String(describing: session.memoryMB)).localized]
        if let exit = session.exit {
            facts.append(Messages.CoreGameDiagnosis.exitText5(String(describing: exit.reason == .signal ? Messages.CoreGameDiagnosis.exitText1.localized : Messages.CoreGameDiagnosis.exitText2.localized), String(describing: exit.status), String(describing: exit.stopRequested ? Messages.CoreGameDiagnosis.exitText3.localized : Messages.CoreGameDiagnosis.exitText4.localized)).localized)
            if exit.normalQuitRequested == true { facts.append(Messages.CoreGameDiagnosis.exitText6.localized) }
        }
        if let interruption = session.interruption {
            facts.append(Messages.CoreGameDiagnosis.interruptionText1(String(describing: interruption.observedAt.ISO8601Format())).localized)
            facts.append(Messages.CoreGameDiagnosis.interruptionText4(String(describing: interruption.resolution == .knownProcessEnded ? Messages.CoreGameDiagnosis.interruptionText2.localized : Messages.CoreGameDiagnosis.interruptionText3.localized)).localized)
        }
        var findings: [GameDiagnosis.Finding] = []
        let externalTermination = session.exit.map { ($0.reason == .signal && [9, 15].contains($0.status)) || ($0.reason == .exit && $0.status == 143) } ?? false
        let canDiagnose = session.state == .failed && !externalTermination
        if canDiagnose {
            for document in documents {
                try Task.checkCancellation()
                let lines = document.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
                var level: String?, crashSectionEnded = false
                for (index, original) in lines.enumerated() {
                    if index % 256 == 0 { try Task.checkCancellation() }
                    let line = String(original.prefix(8192)), lower = line.lowercased()
                    if document.kind == .gameReport && line.contains("A detailed walkthrough of the error") { crashSectionEnded = true }
                    if crashSectionEnded { continue } // A mod list or system description is not the failing stack.
                    if let value = logLevel(line) { level = value }
                    if line.hasPrefix("Exception in thread ") || line.hasPrefix("Error:") || line.hasPrefix("错误:") { level = "FATAL" }
                    let quiet = ["WARN", "INFO", "DEBUG", "TRACE"].contains(level ?? "")
                    if quiet { continue }
                    // JVM reports put all environment data after their initial failure summary.
                    if document.kind == .jvmReport && index > 180 { continue }
                    for rule in rules where rule.needles.contains(where: lower.contains) {
                        if rule.requiresFatalContext && document.kind == .output && level != "ERROR" && level != "FATAL" { continue }
                        let start = max(0, index - 2), end = min(lines.count, index + 7)
                        let excerpt = String(lines[start..<end].joined(separator: "\n").prefix(4096))
                        let evidence = GameDiagnosis.Evidence(documentID: document.id, line: index + 1, excerpt: excerpt)
                        if let existing = findings.firstIndex(where: { $0.id == rule.id }) {
                            if findings[existing].evidence.count < 3 && !findings[existing].evidence.contains(where: { $0.documentID == document.id }) {
                                findings[existing].evidence.append(evidence)
                            }
                        } else {
                            findings.append(.init(id: rule.id, title: rule.title, explanation: rule.explanation, confidence: rule.confidence,
                                                  steps: rule.steps, actions: rule.actions, evidence: [evidence]))
                        }
                    }
                }
            }
        }
        // Keep a specific entrypoint/dependency diagnosis ahead of downstream Mixin/class errors.
        findings.sort { lhs, rhs in
            let li = rules.firstIndex { $0.id == lhs.id } ?? 0, ri = rules.firstIndex { $0.id == rhs.id } ?? 0
            return li < ri
        }
        let summary: String
        if !session.state.isFinished { summary = Messages.CoreGameDiagnosis.summaryText1.localized }
        else if session.state == .interrupted { summary = session.interruption?.explanation ?? Messages.CoreGameDiagnosis.summaryText2.localized }
        else if session.state == .cancelled { summary = Messages.CoreGameDiagnosis.summaryText3.localized }
        else if session.state == .stopped || session.state == .succeeded { summary = session.exit?.explanation ?? Messages.CoreGameDiagnosis.summaryText4.localized }
        else if externalTermination { summary = Messages.CoreGameDiagnosis.summaryText5.localized }
        else if session.exit == nil { summary = Messages.CoreGameDiagnosis.summaryText6(String(describing: session.stage.title)).localized }
        else if findings.isEmpty { summary = Messages.CoreGameDiagnosis.summaryText7.localized }
        else { summary = Messages.CoreGameDiagnosis.summaryText8(Int64(findings.count)).localized }
        if canDiagnose && session.displayFailure != nil && findings.isEmpty {
            let action: GameDiagnosis.Action = session.stage == .account ? .accounts : .settings
            findings.append(.init(id: "preparation", title: Messages.CoreGameDiagnosis.actionText1(String(describing: session.stage.title)).localized, explanation: Messages.CoreGameDiagnosis.actionText2.localized, confidence: .reported,
                                  steps: [Messages.CoreGameDiagnosis.actionText3.localized, Messages.CoreGameDiagnosis.actionText4.localized], actions: [action, .collect],
                                  evidence: [.init(documentID: "preparation", line: 1, excerpt: String((session.displayFailure ?? "").prefix(4096)))]))
        }
        return .init(sessionID: session.id, title: session.title, summary: summary, facts: facts, findings: findings, documents: documents, limitations: limitations)
    }

    private struct Rule {
        let id: String, title: String, explanation: String
        let needles: [String]
        var confidence = GameDiagnosis.Finding.Confidence.reported
        var requiresFatalContext = false
        let steps: [String]
        let actions: [GameDiagnosis.Action]
    }
    private static let levelPattern = try! NSRegularExpression(pattern: #"^(?:\[[^\]\r\n]{1,100}\]\s*)?\[(?:[^\]\r\n]*/)?(TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\]"#)
    private static func logLevel(_ text: String) -> String? {
        guard let match = levelPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for index in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: index), in: text) { return String(text[range]) }
        }
        return nil
    }
    private static let rules: [Rule] = [
        .init(id: "java-version", title: Messages.CoreGameDiagnosis.rulesText1.localized, explanation: Messages.CoreGameDiagnosis.rulesText2.localized,
              needles: ["java.lang.unsupportedclassversionerror"], steps: [Messages.CoreGameDiagnosis.rulesText3.localized, Messages.CoreGameDiagnosis.rulesText4.localized], actions: [.settings, .mods]),
        .init(id: "jvm-options", title: Messages.CoreGameDiagnosis.rulesText5.localized, explanation: Messages.CoreGameDiagnosis.rulesText6.localized,
              needles: ["unrecognized vm option", "unrecognized option:", "invalid maximum heap size", "improperly specified vm option"], steps: [Messages.CoreGameDiagnosis.rulesText7.localized, Messages.CoreGameDiagnosis.rulesText8.localized], actions: [.settings]),
        .init(id: "main-class", title: Messages.CoreGameDiagnosis.rulesText9.localized, explanation: Messages.CoreGameDiagnosis.rulesText10.localized,
              needles: ["could not find or load main class", Messages.CoreGameDiagnosis.rulesText11.localized, Messages.CoreGameDiagnosis.rulesText12.localized], steps: [Messages.CoreGameDiagnosis.rulesText13.localized, Messages.CoreGameDiagnosis.rulesText14.localized], actions: [.repair, .settings, .collect]),
        .init(id: "dependencies", title: Messages.CoreGameDiagnosis.rulesText15.localized, explanation: Messages.CoreGameDiagnosis.rulesText16.localized,
              needles: ["incompatible mods found!", "incompatible mod set!", "modresolutionexception:", "missing or unsupported mandatory dependencies:", "missing mandatory dependencies:", "loading errors encountered:"],
              steps: [Messages.CoreGameDiagnosis.rulesText17.localized, Messages.CoreGameDiagnosis.rulesText18.localized], actions: [.mods, .settings]),
        .init(id: "duplicate-mods", title: Messages.CoreGameDiagnosis.rulesText19.localized, explanation: Messages.CoreGameDiagnosis.rulesText20.localized,
              needles: ["found duplicate mods:", "found a duplicate mod", "duplicate versions for mod id"], steps: [Messages.CoreGameDiagnosis.rulesText21.localized, Messages.CoreGameDiagnosis.rulesText22.localized], actions: [.mods]),
        .init(id: "mod-entrypoint", title: Messages.CoreGameDiagnosis.rulesText23.localized, explanation: Messages.CoreGameDiagnosis.rulesText24.localized,
              needles: ["could not execute entrypoint stage", "loaderexceptionmodcrash: caught exception from", "failed to create mod instance."],
              steps: [Messages.CoreGameDiagnosis.rulesText25.localized, Messages.CoreGameDiagnosis.rulesText26.localized], actions: [.mods]),
        .init(id: "heap-memory", title: Messages.CoreGameDiagnosis.rulesText27.localized, explanation: Messages.CoreGameDiagnosis.rulesText28.localized,
              needles: ["java.lang.outofmemoryerror"], confidence: .possible, requiresFatalContext: true,
              steps: [Messages.CoreGameDiagnosis.rulesText29.localized, Messages.CoreGameDiagnosis.rulesText30.localized], actions: [.settings, .mods]),
        .init(id: "native-memory", title: Messages.CoreGameDiagnosis.rulesText31.localized, explanation: Messages.CoreGameDiagnosis.rulesText32.localized,
              needles: ["there is insufficient memory for the java runtime environment to continue", "could not reserve enough space for"],
              steps: [Messages.CoreGameDiagnosis.rulesText33.localized, Messages.CoreGameDiagnosis.rulesText34.localized], actions: [.settings]),
        .init(id: "native-architecture", title: Messages.CoreGameDiagnosis.rulesText35.localized, explanation: Messages.CoreGameDiagnosis.rulesText36.localized,
              needles: ["incompatible architecture (have", "bad cpu type in executable"],
              steps: [Messages.CoreGameDiagnosis.rulesText37.localized, Messages.CoreGameDiagnosis.rulesText38.localized], actions: [.settings, .mods]),
        .init(id: "macos-main-thread", title: Messages.CoreGameDiagnosis.rulesText39.localized, explanation: Messages.CoreGameDiagnosis.rulesText40.localized,
              needles: ["glfw may only be used on the main thread", "nswindow should only be instantiated on the main thread", "nswindow drag regions should only be invalidated on the main thread", "glfw error before init: [0x10008]cocoa: failed to find service port for display"],
              steps: [Messages.CoreGameDiagnosis.rulesText41.localized, Messages.CoreGameDiagnosis.rulesText42.localized], actions: [.settings, .collect]),
        .init(id: "config", title: Messages.CoreGameDiagnosis.rulesText43.localized, explanation: Messages.CoreGameDiagnosis.rulesText44.localized,
              needles: ["failed loading config file"], requiresFatalContext: true,
              steps: [Messages.CoreGameDiagnosis.rulesText45.localized, Messages.CoreGameDiagnosis.rulesText46.localized], actions: [.files, .mods]),
        .init(id: "mixin", title: Messages.CoreGameDiagnosis.rulesText47.localized, explanation: Messages.CoreGameDiagnosis.rulesText48.localized,
              needles: ["mixinapplyerror", "mixin apply for mod", "mixin apply failed", "mixin prepare failed", "critical injection failure"], confidence: .possible, requiresFatalContext: true,
              steps: [Messages.CoreGameDiagnosis.rulesText49.localized, Messages.CoreGameDiagnosis.rulesText50.localized], actions: [.mods, .collect]),
        .init(id: "native-crash", title: Messages.CoreGameDiagnosis.rulesText51.localized, explanation: Messages.CoreGameDiagnosis.rulesText52.localized,
              needles: ["a fatal error has been detected by the java runtime environment"], steps: [Messages.CoreGameDiagnosis.rulesText53.localized, Messages.CoreGameDiagnosis.rulesText54.localized], actions: [.settings, .collect]),
        .init(id: "debug-crash", title: Messages.CoreGameDiagnosis.rulesText55.localized, explanation: Messages.CoreGameDiagnosis.rulesText56.localized,
              needles: ["manually triggered debug crash"], steps: [Messages.CoreGameDiagnosis.rulesText57.localized], actions: [.collect])
    ]
}
