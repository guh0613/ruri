import RuriLocalization
import Foundation

public struct GameDiagnosticDocument: Identifiable, Sendable {
    public enum Kind: String, Sendable { case preparation, output, gameReport, jvmReport, launcher, systemReport }
    public let id: String
    public let relativePath: String?
    public let title: String
    public let kind: Kind
    public let text: String
    public var isTail = false
    public var truncated = false
    public var gameRelativePath: String? = nil
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
            case .settings: Messages.CoreGameDiagnosis.checkInstanceSettings.localized
            case .mods: Messages.CoreGameDiagnosis.manageMods.localized
            case .accounts: Messages.CoreGameDiagnosis.checkAccount.localized
            case .repair: Messages.CoreGameDiagnosis.repairInstallationFiles.localized
            case .files: Messages.CoreGameDiagnosis.viewRunFiles.localized
            case .collect: Messages.CoreGameDiagnosis.collectDiagnosticReports.localized
            }
        }
    }
    public struct Finding: Identifiable, Sendable {
        public enum Confidence: String, Sendable {
            case reported, possible
            public var title: String { switch self { case .reported: Messages.CoreGameDiagnosis.logExplicitReport.localized; case .possible: Messages.CoreGameDiagnosis.cluesNeedingVerification.localized } }
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
/// Analysis defaults to saved evidence. Explicit collection can also snapshot
/// matching game-native logs; log text never supplies a path.
public enum GameDiagnosticAnalyzer {
    public static func load(paths: LauncherPaths, session: GameSession, includeGameLogs: Bool = false) throws -> GameDiagnosis {
        let evidence = try GameEvidenceCollector.collect(paths: paths, session: session, includeGameLogs: includeGameLogs)
        return try analyze(session: session, documents: evidence.documents, limitations: evidence.limitations)
    }

    public static func analyze(session: GameSession, documents: [GameDiagnosticDocument], limitations: [String] = []) throws -> GameDiagnosis {
        var facts = [Messages.CoreGameDiagnosis.lastRecordedPhase(session.stage.title).localized, "Minecraft \(session.gameVersion) · \(session.loader) \(session.loaderVersion ?? "")",
                     Messages.CoreGameDiagnosis.memoryLimit(String(describing: session.java ?? Messages.CoreGameDiagnosis.javaNotRecorded.localized), String(describing: session.memoryMB)).localized]
        if let exit = session.exit {
            facts.append(Messages.CoreGameDiagnosis.exitSummary(String(describing: exit.reason == .signal ? Messages.CoreGameDiagnosis.terminationSignal.localized : Messages.CoreGameDiagnosis.exitCode.localized), String(describing: exit.status), String(describing: exit.stopRequested ? Messages.CoreGameDiagnosis.hasExitStatus.localized : Messages.CoreGameDiagnosis.noExitStatus.localized)).localized)
            if exit.normalQuitRequested == true { facts.append(Messages.CoreGameDiagnosis.normalExitRequested.localized) }
        }
        if let interruption = session.interruption {
            facts.append(Messages.CoreGameDiagnosis.recoveryRecordTime(String(describing: interruption.observedAt.ISO8601Format())).localized)
            facts.append(Messages.CoreGameDiagnosis.recoveryBasis(String(describing: interruption.resolution == .knownProcessEnded ? Messages.CoreGameDiagnosis.processIdentityInvalid.localized : Messages.CoreGameDiagnosis.userConfirmedExit.localized)).localized)
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
        if !session.state.isFinished { summary = Messages.CoreGameDiagnosis.runWithoutExitRecord.localized }
        else if session.state == .interrupted { summary = session.interruption?.explanation ?? Messages.CoreGameDiagnosis.monitoringInterrupted.localized }
        else if session.state == .cancelled { summary = Messages.CoreGameDiagnosis.launchCancelled.localized }
        else if session.state == .stopped || session.state == .succeeded { summary = session.exit?.explanation ?? Messages.CoreGameDiagnosis.runCompleted.localized }
        else if externalTermination { summary = Messages.CoreGameDiagnosis.processTerminated.localized }
        else if session.exit == nil { summary = Messages.CoreGameDiagnosis.launchPreparationFailed(session.stage.title).localized }
        else if findings.isEmpty { summary = Messages.CoreGameDiagnosis.confirmedAbnormalExit.localized }
        else { summary = Messages.CoreGameDiagnosis.relatedErrorCount(Int64(findings.count)).localized }
        if canDiagnose && session.displayFailure != nil && findings.isEmpty {
            let action: GameDiagnosis.Action = session.stage == .account ? .accounts : .settings
            findings.append(.init(id: "preparation", title: Messages.CoreGameDiagnosis.actionFailed(session.stage.title).localized, explanation: Messages.CoreGameDiagnosis.preparationError.localized, confidence: .reported,
                                  steps: [Messages.CoreGameDiagnosis.guidanceCheckErrors.localized, Messages.CoreGameDiagnosis.guidanceCollectRetry.localized], actions: [action, .collect],
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
        .init(id: "java-version", title: Messages.CoreGameDiagnosis.classVersionUnreadable.localized, explanation: Messages.CoreGameDiagnosis.classVersionUnsupported.localized,
              needles: ["java.lang.unsupportedclassversionerror"], steps: [Messages.CoreGameDiagnosis.classVersionCheck.localized, Messages.CoreGameDiagnosis.classVersionModCheck.localized], actions: [.settings, .mods]),
        .init(id: "jvm-options", title: Messages.CoreGameDiagnosis.launchArgumentRejected.localized, explanation: Messages.CoreGameDiagnosis.launchArgumentExplanation.localized,
              needles: ["unrecognized vm option", "unrecognized option:", "invalid maximum heap size", "improperly specified vm option"], steps: [Messages.CoreGameDiagnosis.launchArgumentCheck.localized, Messages.CoreGameDiagnosis.launchArgumentRetry.localized], actions: [.settings]),
        .init(id: "main-class", title: Messages.CoreGameDiagnosis.missingLaunchEntry.localized, explanation: Messages.CoreGameDiagnosis.missingMainClassExplanation.localized,
              needles: ["could not find or load main class", Messages.CoreGameDiagnosis.missingMainClass.localized, Messages.CoreGameDiagnosis.missingMainClassCjk.localized], steps: [Messages.CoreGameDiagnosis.missingMainClassCheck.localized, Messages.CoreGameDiagnosis.missingMainClassReport.localized], actions: [.repair, .settings, .collect]),
        .init(id: "dependencies", title: Messages.CoreGameDiagnosis.loaderModConflict.localized, explanation: Messages.CoreGameDiagnosis.loaderModConflictExplanation.localized,
              needles: ["incompatible mods found!", "incompatible mod set!", "modresolutionexception:", "missing or unsupported mandatory dependencies:", "missing mandatory dependencies:", "loading errors encountered:"],
              steps: [Messages.CoreGameDiagnosis.loaderModConflictCheck.localized, Messages.CoreGameDiagnosis.loaderModConflictRetry.localized], actions: [.mods, .settings]),
        .init(id: "duplicate-mods", title: Messages.CoreGameDiagnosis.duplicateMod.localized, explanation: Messages.CoreGameDiagnosis.duplicateModExplanation.localized,
              needles: ["found duplicate mods:", "found a duplicate mod", "duplicate versions for mod id"], steps: [Messages.CoreGameDiagnosis.duplicateModCheck.localized, Messages.CoreGameDiagnosis.duplicateModRetry.localized], actions: [.mods]),
        .init(id: "mod-entrypoint", title: Messages.CoreGameDiagnosis.modInitializationFailure.localized, explanation: Messages.CoreGameDiagnosis.modInitializationExplanation.localized,
              needles: ["could not execute entrypoint stage", "loaderexceptionmodcrash: caught exception from", "failed to create mod instance."],
              steps: [Messages.CoreGameDiagnosis.modInitializationCheck.localized, Messages.CoreGameDiagnosis.modInitializationRetry.localized], actions: [.mods]),
        .init(id: "heap-memory", title: Messages.CoreGameDiagnosis.outOfMemory.localized, explanation: Messages.CoreGameDiagnosis.outOfMemoryExplanation.localized,
              needles: ["java.lang.outofmemoryerror"], confidence: .possible, requiresFatalContext: true,
              steps: [Messages.CoreGameDiagnosis.outOfMemoryTypes.localized, Messages.CoreGameDiagnosis.outOfMemoryCheck.localized], actions: [.settings, .mods]),
        .init(id: "native-memory", title: Messages.CoreGameDiagnosis.nativeMemoryAllocationFailure.localized, explanation: Messages.CoreGameDiagnosis.nativeMemoryAllocationExplanation.localized,
              needles: ["there is insufficient memory for the java runtime environment to continue", "could not reserve enough space for"],
              steps: [Messages.CoreGameDiagnosis.nativeMemoryCheck.localized, Messages.CoreGameDiagnosis.nativeMemoryRetry.localized], actions: [.settings]),
        .init(id: "native-architecture", title: Messages.CoreGameDiagnosis.architectureMismatch.localized, explanation: Messages.CoreGameDiagnosis.architectureMismatchExplanation.localized,
              needles: ["incompatible architecture (have", "bad cpu type in executable"],
              steps: [Messages.CoreGameDiagnosis.architectureCheck.localized, Messages.CoreGameDiagnosis.architectureModCheck.localized], actions: [.settings, .mods]),
        .init(id: "macos-main-thread", title: Messages.CoreGameDiagnosis.mainThreadViolation.localized, explanation: Messages.CoreGameDiagnosis.mainThreadViolationExplanation.localized,
              needles: ["glfw may only be used on the main thread", "nswindow should only be instantiated on the main thread", "nswindow drag regions should only be invalidated on the main thread", "glfw error before init: [0x10008]cocoa: failed to find service port for display"],
              steps: [Messages.CoreGameDiagnosis.mainThreadCheck.localized, Messages.CoreGameDiagnosis.mainThreadReport.localized], actions: [.settings, .collect]),
        .init(id: "config", title: Messages.CoreGameDiagnosis.configReadFailure.localized, explanation: Messages.CoreGameDiagnosis.configReadExplanation.localized,
              needles: ["failed loading config file"], requiresFatalContext: true,
              steps: [Messages.CoreGameDiagnosis.configBackup.localized, Messages.CoreGameDiagnosis.configRepair.localized], actions: [.files, .mods]),
        .init(id: "mixin", title: Messages.CoreGameDiagnosis.mixinApplyFailure.localized, explanation: Messages.CoreGameDiagnosis.mixinApplyExplanation.localized,
              needles: ["mixinapplyerror", "mixin apply for mod", "mixin apply failed", "mixin prepare failed", "critical injection failure"], confidence: .possible, requiresFatalContext: true,
              steps: [Messages.CoreGameDiagnosis.mixinDependencyCheck.localized, Messages.CoreGameDiagnosis.mixinModCheck.localized], actions: [.mods, .collect]),
        .init(id: "native-crash", title: Messages.CoreGameDiagnosis.jvmCrash.localized, explanation: Messages.CoreGameDiagnosis.jvmCrashExplanation.localized,
              needles: ["a fatal error has been detected by the java runtime environment"], steps: [Messages.CoreGameDiagnosis.jvmCrashReport.localized, Messages.CoreGameDiagnosis.jvmCrashCheck.localized], actions: [.settings, .collect]),
        .init(id: "debug-crash", title: Messages.CoreGameDiagnosis.debugCrash.localized, explanation: Messages.CoreGameDiagnosis.debugCrashExplanation.localized,
              needles: ["manually triggered debug crash"], steps: [Messages.CoreGameDiagnosis.debugCrashRetry.localized], actions: [.collect])
    ]
}
