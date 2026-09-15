import Foundation
import Testing
import RuriLocalization
@testable import RuriCore

struct LauncherJournalTests {
    @Test func taskLifecycleKeepsStagesAndOneNotification() throws {
        var journal = LauncherJournal()
        let id = journal.begin(.verbatim("Install Minecraft"))
        let session = UUID(), file = URL(fileURLWithPath: "/tmp/kept-copy")
        journal.linkSession(session, to: id)
        #expect(journal.entries[0].detail == nil)
        #expect(journal.entries[0].steps.isEmpty)
        #expect(journal.entries[0].sessionID == session)
        for count in 1...120 { journal.progress(id, InstallProgress("Assets", completed: count, total: 120)) }
        #expect(journal.entries[0].steps.count == 1)
        #expect(journal.entries[0].progress.completed == 120)
        journal.annotate(id, message: .verbatim("Preserved copy"), level: .warning, sessionID: session, fileURL: file)
        journal.finish(id, status: .completed)
        #expect(journal.entries.count == 1)
        #expect(journal.notifications.count == 1)
        #expect(journal.unreadCount == 1)
        #expect(journal.entries[0].level == .warning)
        #expect(journal.entries[0].sessionID == session)
        #expect(journal.entries[0].fileURL == file)
        journal.markRead(id)
        #expect(journal.unreadCount == 0)
        journal.progress(id, InstallProgress("Late callback"))
        journal.finish(id, status: .failed)
        #expect(journal.entries[0].status == .completed)
        #expect(journal.entries[0].steps.count == 2)
    }

    @Test func cancellationDistinguishesCleanExitFromRecoveryWarning() {
        var journal = LauncherJournal()
        let clean = journal.begin(.verbatim("Clean cancellation"))
        journal.finish(clean, status: .cancelled)
        #expect(journal.unreadCount == 0)
        let pending = journal.begin(.verbatim("Copy with recovery files"))
        journal.annotate(pending, message: .verbatim("Review preserved files"), level: .error,
                         fileURL: URL(fileURLWithPath: "/tmp/recovery"))
        journal.finish(pending, status: .cancelled)
        #expect(journal.entries[0].status == .cancelled)
        #expect(journal.entries[0].level == .warning)
        #expect(journal.notifications.count == 1)
    }

    @Test func boundedHistoryAndClearPreserveRunningTasks() {
        var journal = LauncherJournal()
        let id = journal.begin(.verbatim("Long running"))
        for index in 0..<LauncherJournal.capacity + 20 { journal.record(.verbatim("Event \(index)")) }
        for index in 0..<LauncherJournal.stepCapacity + 20 { journal.progress(id, InstallProgress("Stage \(index)")) }
        #expect(journal.entries.count == LauncherJournal.capacity + 1)
        #expect(journal.entries.first(where: { $0.id == id })?.steps.count == LauncherJournal.stepCapacity)
        journal.clearFinished()
        #expect(journal.entries.map(\.id) == [id])
        #expect(journal.unreadCount == 0)
        journal.finish(id, status: .completed)
        #expect(journal.unreadCount == 1)
    }

    @Test func repeatedPollingDoesNotReopenReadNotification() {
        var journal = LauncherJournal()
        let date = Date(), session = UUID()
        let id = journal.record(.verbatim("Unavailable"), level: .warning, sessionID: session, date: date)
        journal.markRead(id)
        #expect(journal.record(.verbatim("Unavailable"), level: .warning, sessionID: session, date: date.addingTimeInterval(10)) == id)
        #expect(journal.unreadCount == 0)
        let other = journal.record(.verbatim("Unavailable"), level: .warning, sessionID: UUID(), date: date.addingTimeInterval(10))
        #expect(other != id)
        #expect(journal.unreadCount == 1)
    }

    @Test func finishingOldTaskRetainsItsNewResult() {
        var journal = LauncherJournal()
        let id = journal.begin(.verbatim("Long running"), date: .distantPast)
        for index in 0..<LauncherJournal.capacity { journal.record(.verbatim("Event \(index)")) }
        journal.finish(id, status: .completed)
        #expect(journal.entries.count == LauncherJournal.capacity)
        #expect(journal.notifications.first?.id == id)
    }

    @Test func persistedHistoryRestoresReadStateLinksAndInterruptedWork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        var journal = LauncherJournal()
        let session = UUID(), file = root.appendingPathComponent("export.zip")
        let done = journal.record(.verbatim("Exported"), sessionID: session, fileURL: file)
        journal.markRead(done)
        let running = journal.begin(.verbatim("Install"))
        journal.progress(running, InstallProgress("Downloading", completed: 2, total: 10))
        try LauncherJournalStore.save(journal, previous: LauncherJournal(), paths: paths)
        var loaded = try LauncherJournalStore.load(paths: paths)
        #expect(loaded.entries == journal.entries)
        loaded.recoverInterrupted()
        #expect(loaded.entries.first(where: { $0.id == running })?.status == .interrupted)
        #expect(loaded.entries.first(where: { $0.id == done })?.isRead == true)
        #expect(loaded.unreadCount == 1)
        loaded.markRead(running)
        loaded.recoverInterrupted()
        #expect(loaded.unreadCount == 0)
        try LauncherJournalStore.save(loaded, previous: journal, paths: paths)
        #expect(try LauncherJournalStore.load(paths: paths).entries == loaded.entries)
    }

    @Test func corruptHistoryIsNotOverwrittenByLoading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root), url = GameHistoryStore.databaseURL(paths: LauncherPaths(root: root))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data("not a database".utf8)
        try original.write(to: url)
        #expect(throws: (any Error).self) { try LauncherJournalStore.load(paths: paths) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func storedMessagesRedactCredentialsAndBoundLongInput() {
        var journal = LauncherJournal()
        let id = journal.begin(.verbatim("access_token=secret-one"))
        journal.progress(id, InstallProgress("Authorization: Bearer secret-two"))
        journal.finish(id, status: .failed, detail: "refresh_token=secret-three\n" + String(repeating: "x", count: 10000))
        let entry = journal.entries[0]
        #expect(!entry.title.contains("secret-one"))
        #expect(!entry.progress.stage.contains("secret-two"))
        #expect(entry.detail?.contains("secret-three") == false)
        #expect((entry.detail?.count ?? 0) <= 8192)
    }
}
