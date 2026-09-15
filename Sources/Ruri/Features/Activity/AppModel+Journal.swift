import AppKit
import Foundation
import RuriCore
import RuriLocalization
import UniformTypeIdentifiers

enum LauncherActivityContext {
    @TaskLocal static var id: UUID?
}

extension AppModel {
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
            journal.record(message, level: level, kind: sessionID == nil ? .launcher : .game,
                           sessionID: sessionID, fileURL: fileURL)
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
