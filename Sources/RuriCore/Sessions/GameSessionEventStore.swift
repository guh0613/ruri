import Foundation
import CSQLite
import RuriLocalization

/// Low-frequency launcher/client events, not a second copy of game output.
public enum GameSessionEventStore {
    public struct Entry: Codable, Identifiable, Equatable, Sendable {
        public let id: UUID
        public let date: Date
        public let source: String
        public let text: String
    }
    static func append(_ text: String, source: String = "launcher", sessionID: UUID, paths: LauncherPaths, date: Date = Date(), id: UUID = UUID()) throws {
        let entry = Entry(id: id, date: date, source: source, text: String(text.prefix(8192)))
        let data = try JSONEncoder().encode(entry)
        try GameHistoryStore.withDatabase(paths: paths) { db in
            // One atomic insert: concurrent clients share the same event budget.
            try db.execute("""
                INSERT OR IGNORE INTO runtime_events(id, session_id, date, payload)
                SELECT ?, ?, ?, ? WHERE
                    (SELECT count(*) FROM runtime_events WHERE session_id=?) < 512 AND
                    (SELECT coalesce(sum(length(payload)), 0) FROM runtime_events WHERE session_id=?) + ? <= 262144
                """, [.text(id.uuidString), .text(sessionID.uuidString), .real(date.timeIntervalSince1970), .blob(data),
                      .text(sessionID.uuidString), .text(sessionID.uuidString), .integer(data.count)])
        }
    }
    public static func entries(paths: LauncherPaths, sessionID: UUID) throws -> [Entry] {
        try GameHistoryStore.withDatabase(paths: paths) { db in
            var result: [Entry] = []
            try db.rows("SELECT payload FROM runtime_events WHERE session_id=? ORDER BY date, id LIMIT 512", [.text(sessionID.uuidString)]) { statement in
                guard let data = HistoryDatabase.data(statement, 0) else { throw POSIXError(.EINVAL) }
                result.append(try JSONDecoder().decode(Entry.self, from: data))
            }
            return result
        }
    }
    public static func text(paths: LauncherPaths, session: GameSession) throws -> String {
        var lines = session.events.map { ($0.date, $0.displayMessage) }
        lines += try entries(paths: paths, sessionID: session.id).map { ($0.date, $0.text) }
        if let failure = session.displayFailure { lines.append((session.updatedAt, failure)) }
        return lines.sorted { $0.0 < $1.0 }.map { "[Ruri] \($0.0.ISO8601Format()) \($0.1)" }.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }
}
