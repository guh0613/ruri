import Foundation
import RuriLocalization

public struct GameEvidenceSnapshot: Sendable {
    public let documents: [GameDiagnosticDocument]
    public let limitations: [String]
}

/// Explicit collection/analysis, never a periodic in-game activity. Native logs
/// are primary; database events and bounded process output cover their gaps.
public enum GameEvidenceCollector {
    /// The report picker shares the same sources and session matching as export,
    /// without reading ordinary game logs just to list a few crash reports.
    public static func reports(paths: LauncherPaths, session: GameSession) throws -> [GameDiagnosticDocument] {
        var budget = 12 * 1_048_576
        var documents: [GameDiagnosticDocument] = []
        var names: Set<String> = []
        let sources = try GameLogSources.native(paths: paths, session: session) + GameLogSources.saved(paths: paths, session: session)
        for source in sources where [.gameReport, .jvmReport, .systemReport].contains(source.kind) {
            let name = session.evidence.first { $0.relativePath == source.reference.relativePath }?.name ?? source.title
            guard !names.contains(name), budget > 0 else { continue }
            let parts = try GameNativeLogCollector.read(source, budget: &budget)
            guard let first = parts.first else { continue }
            names.insert(name)
            let text = parts.map(\.text).joined(separator: "\n" + Messages.CoreGameSession.truncatedLogNotice.localized + "\n")
            documents.append(.init(id: source.id, relativePath: first.relativePath, title: name, kind: source.kind,
                                   text: text, truncated: parts.contains(where: \.truncated), gameRelativePath: first.gameRelativePath))
        }
        if !documents.contains(where: { $0.kind == .systemReport }) {
            documents += try GameSystemReportCollector.collect(session: session, budget: &budget).documents
        }
        return documents
    }

    public static func collect(paths: LauncherPaths, session: GameSession, includeGameLogs: Bool = false) throws -> GameEvidenceSnapshot {
        var documents: [GameDiagnosticDocument] = [], limitations: [String] = []
        if let failure = session.displayFailure {
            documents.append(.init(id: "preparation", relativePath: nil, title: session.stage.title, kind: .preparation, text: failure))
        }
        var budget = 12 * 1_048_576
        var nativeNames: Set<String> = []
        if includeGameLogs {
            do {
                let snapshot = try GameNativeLogCollector.collect(paths: paths, session: session, budget: &budget)
                documents += snapshot.documents; limitations += snapshot.limitations; nativeNames = snapshot.names
            } catch is CancellationError { throw CancellationError() }
            catch { limitations.append(Messages.NativeGameLogs.collectionFailed.localized) }
        }
        if session.artifactState == .expired { limitations.append(Messages.SessionRuntime.artifactsExpired.localized) }
        budget += 4 * 1_048_576
        let saved = try GameLogSources.saved(paths: paths, session: session)
        if session.artifactState != .expired {
            let directory = try GameSessionStore.directory(paths: paths, instanceID: session.instanceID, sessionID: session.id)
            for name in session.evidence.map(\.relativePath) + ["console.log", "console-tail.log"] where !saved.contains(where: { $0.reference.relativePath == name }) {
                if session.evidence.contains(where: { $0.relativePath == name }) || FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
                    limitations.append(Messages.CoreGameDiagnosis.unreadableReport(name, Messages.CoreGameSession.logNotRegularFile.localized).localized)
                }
            }
        }
        for source in saved {
            if let original = session.evidence.first(where: { $0.relativePath == source.reference.relativePath }), nativeNames.contains(original.name) { continue }
            do {
                let items = try GameNativeLogCollector.read(source, budget: &budget)
                documents += items
                if items.contains(where: \.truncated) { limitations.append(Messages.CoreGameDiagnosis.boundedTail(source.title).localized) }
            } catch is CancellationError { throw CancellationError() }
            catch { limitations.append(Messages.CoreGameDiagnosis.unreadableReport(source.title, error.localizedDescription).localized) }
        }
        do {
            let text = try GameSessionStore.logTail(paths: paths, session: session, byteLimit: 262_144, source: .launcher)
            if !text.isEmpty { documents.append(.init(id: "launcher.log", relativePath: nil, title: Messages.SessionRuntime.launcherEvents.localized, kind: .preparation, text: text)) }
            let related = try LauncherJournalStore.related(paths: paths, sessionID: session.id)
            var activity = ""
            for entry in related where activity.utf8.count < 262_144 {
                activity += ([entry.startedAt.ISO8601Format() + " " + entry.title] + entry.steps.map { $0.date.ISO8601Format() + " " + $0.message.localized } + [entry.detail ?? ""]).joined(separator: "\n") + "\n"
            }
            if !activity.isEmpty { documents.append(.init(id: "launcher-activity", relativePath: nil, title: Messages.SessionUI.launcherActivity.localized, kind: .launcher, text: GameSessionStore.bounded(activity, byteLimit: 262_144))) }
        } catch { limitations.append(Messages.CoreGameDiagnosis.sessionLogReadFailure(error.localizedDescription).localized) }
        if includeGameLogs {
            if !session.state.isFinished, session.controlEndpoint != nil {
                do {
                    let text = try GameMonitorClient.logPreview(paths: paths, session: session)
                    if !text.isEmpty { documents.append(.init(id: "live-console", relativePath: nil, title: Messages.SessionUI.processOutput.localized, kind: .output, text: text, truncated: true)) }
                } catch { limitations.append(Messages.SessionUI.noLiveConnection.localized) }
            }
            if !documents.contains(where: { $0.kind == .systemReport }) {
                let system = try GameSystemReportCollector.collect(session: session, budget: &budget)
                documents += system.documents; limitations += system.limitations
            }
        }
        return .init(documents: documents, limitations: limitations)
    }
}
