import Foundation
import RuriLocalization

/// Shares the session database, but stores one activity per row. GUI snapshots
/// are coalesced before reaching this store; unchanged entries do not write.
public enum LauncherJournalStore {
    public static func load(paths: LauncherPaths) throws -> LauncherJournal {
        return try GameHistoryStore.withDatabase(paths: paths) { db in
            var entries: [LauncherLogEntry] = []
            try db.rows("SELECT payload FROM launcher_events ORDER BY updated DESC LIMIT 1000") { statement in
                guard let data = HistoryDatabase.data(statement, 0) else { throw POSIXError(.EINVAL) }
                let entry = try JSONDecoder().decode(LauncherLogEntry.self, from: data)
                guard entry.steps.count <= LauncherJournal.stepCapacity else { throw POSIXError(.EINVAL) }
                entries.append(entry)
            }
            return LauncherJournal(entries: entries)
        }
    }
    public static func save(_ journal: LauncherJournal, previous: LauncherJournal, paths: LauncherPaths) throws {
        let old = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.id, $0) })
        let ids = Set(journal.entries.map(\.id))
        let changed = journal.entries.filter { old[$0.id] != $0 }
        let removed = previous.entries.filter { !ids.contains($0.id) }.map(\.id)
        guard !changed.isEmpty || !removed.isEmpty else { return }
        try GameHistoryStore.withDatabase(paths: paths) { db in
            try db.transaction {
                for entry in changed { try store(entry, db: db) }
                for id in removed { try db.execute("DELETE FROM launcher_events WHERE id=?", [.text(id.uuidString)]) }
                try db.execute("DELETE FROM launcher_events WHERE running=0 AND id NOT IN (SELECT id FROM launcher_events WHERE running=0 ORDER BY updated DESC LIMIT ?)", [.integer(LauncherJournal.capacity)])
            }
        }
    }
    static func related(paths: LauncherPaths, sessionID: UUID) throws -> [LauncherLogEntry] {
        try GameHistoryStore.withDatabase(paths: paths) { db in
            var result: [LauncherLogEntry] = []
            try db.rows("SELECT payload FROM launcher_events WHERE session_id=? ORDER BY updated LIMIT 500", [.text(sessionID.uuidString)]) { statement in
                guard let data = HistoryDatabase.data(statement, 0) else { throw POSIXError(.EINVAL) }
                result.append(try JSONDecoder().decode(LauncherLogEntry.self, from: data))
            }
            return result
        }
    }
    private static func store(_ entry: LauncherLogEntry, db: HistoryDatabase) throws {
        let data = try JSONEncoder().encode(entry)
        guard data.count <= 1_048_576, entry.steps.count <= LauncherJournal.stepCapacity else { throw POSIXError(.EFBIG) }
        try db.execute("""
            INSERT INTO launcher_events(id, session_id, updated, running, payload) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET session_id=excluded.session_id, updated=excluded.updated, running=excluded.running, payload=excluded.payload
            WHERE launcher_events.payload<>excluded.payload
            """, [.text(entry.id.uuidString), entry.sessionID.map { .text($0.uuidString) } ?? .null,
                  .real(entry.updatedAt.timeIntervalSince1970), .integer(entry.status == .running ? 1 : 0), .blob(data)])
    }
}
