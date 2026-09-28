import AppKit
import Foundation
import RuriCore
import RuriLocalization
import UniformTypeIdentifiers

enum LauncherActivityContext {
    @TaskLocal static var id: UUID?
}

/// How a task that succeeds cleanly is kept. Failures and warnings are always
/// kept and announced.
enum TaskRecording {
    /// Announced when it ran long enough to walk away from, or finished while
    /// the launcher was in the background.
    case standard
    /// Logged without a notification; its outcome has its own place, like a game run.
    case logged
    /// Not kept; the interface shows the result as it happens.
    case transient
}

extension AppModel {
    static let noticeableTaskDuration: TimeInterval = 10

    func finishTask(_ id: UUID, recording: TaskRecording) {
        guard let entry = journal.entries.first(where: { $0.id == id }) else { return }
        let long = Date().timeIntervalSince(entry.startedAt) >= Self.noticeableTaskDuration || !NSApp.isActive
        journal.finish(id, status: .completed, announce: recording == .standard && long)
        if recording == .transient, entry.sessionID == nil, entry.fileURL == nil, !entry.needsAttention { journal.discard(id) }
    }

    func report(_ message: String, level: LauncherLogEntry.Level = .info,
                sessionID: UUID? = nil, fileURL: URL? = nil) {
        report(.verbatim(message), level: level, sessionID: sessionID, fileURL: fileURL)
    }

    func report(_ message: LocalizedMessage, level: LauncherLogEntry.Level = .info,
                sessionID: UUID? = nil, fileURL: URL? = nil) {
        if let id = LauncherActivityContext.id,
           journal.entries.contains(where: { $0.id == id && $0.status == .running }) {
            journal.annotate(id, message: message, level: level, sessionID: sessionID, fileURL: fileURL)
        } else {
            // Confirmations already show where they happen; only problems notify.
            journal.record(message, level: level, kind: sessionID == nil ? .launcher : .game,
                           notify: level == .warning || level == .error, sessionID: sessionID, fileURL: fileURL)
        }
        persistJournal()
    }

    func persistJournal() {
        guard journalPersistenceEnabled, journalWriteTask == nil else { return }
        journalWriteTask = Task {
            defer { journalWriteTask = nil }
            while journal != persistedJournal {
                let snapshot = journal, previous = persistedJournal, paths = basePaths
                do {
                    try await Task.detached(priority: .utility) { try LauncherJournalStore.save(snapshot, previous: previous, paths: paths) }.value
                    persistedJournal = snapshot; journalStorageError = nil
                } catch { journalStorageError = Messages.LauncherLog.historyWriteFailed.localized; return }
            }
        }
    }

    func markLogRead(_ id: UUID? = nil) {
        journal.markRead(id)
        persistJournal()
    }

    func showLauncherLog(_ id: UUID? = nil) {
        selectedLogID = id
        logNavigationID = UUID()
        page = .activity
        if let id { markLogRead(id) }
    }

    /// Game results open the run itself; everything else opens its log entry.
    func openLogEntry(_ entry: LauncherLogEntry) {
        if let sessionID = entry.sessionID { markLogRead(entry.id); showSession(sessionID) }
        else { showLauncherLog(entry.id) }
    }

    func clearLogHistory() {
        journal.clearFinished()
        if !journal.entries.contains(where: { $0.id == selectedLogID }) { selectedLogID = nil }
        persistJournal()
    }

    func exportLauncherLog(_ entries: [LauncherLogEntry]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "ruri-launcher.log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = entries.map(\.plainText).joined(separator: "\n\n")
            try GameShareRedactor().redact(text).write(to: url, atomically: true, encoding: .utf8)
            report(Messages.LauncherLog.exported, level: .success, fileURL: url)
        } catch { self.error = error.localizedDescription }
    }
}
