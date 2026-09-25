import Foundation
import Testing
@testable import RuriCore

struct LauncherJournalDatabaseTests {
    @Test func deltaWritesKeepOtherClientsEntries() throws {
        let (paths, _) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var journal = try LauncherJournalStore.load(paths: paths)
        let oldID = journal.record(.verbatim("existing activity"))
        try LauncherJournalStore.save(journal, previous: LauncherJournal(), paths: paths)
        let initial = try LauncherJournalStore.load(paths: paths)
        var first = initial, second = initial
        let firstID = first.record(.verbatim("first client"))
        let secondID = second.record(.verbatim("second client"))
        try LauncherJournalStore.save(first, previous: initial, paths: paths)
        try LauncherJournalStore.save(second, previous: initial, paths: paths)
        let merged = try LauncherJournalStore.load(paths: paths)
        #expect(Set(merged.entries.map(\.id)) == [oldID, firstID, secondID])
        try LauncherJournalStore.save(second, previous: second, paths: paths)
        #expect(try LauncherJournalStore.load(paths: paths) == merged)
        let previousFirst = first
        first.clearFinished()
        try LauncherJournalStore.save(first, previous: previousFirst, paths: paths)
        #expect(try LauncherJournalStore.load(paths: paths).entries.map(\.id) == [secondID])
    }
}
