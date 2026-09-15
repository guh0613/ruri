import Foundation
import Darwin
import CSQLite
import RuriLocalization

public struct GameHistorySummary: Sendable {
    public var seconds: Double = 0
    public var playCount: Int = 0
    public var lastPlayed: Date?
    public init() {}
}

public struct GameHistoryQuery: Sendable {
    public var instanceID: UUID?
    public var since: Date?
    public var search: String
    public var problemsOnly: Bool
    public var limit: Int
    public var offset: Int
    public init(instanceID: UUID? = nil, since: Date? = nil, search: String = "", problemsOnly: Bool = false, limit: Int = 100, offset: Int = 0) {
        self.instanceID = instanceID; self.since = since; self.search = search; self.problemsOnly = problemsOnly; self.limit = limit; self.offset = offset
    }
}

/// Permanent, indexed metadata. Large diagnostic files remain disposable and
/// never enter this database. The GameSession payload is the versioned snapshot
/// used to inspect a historical run, not a live process/liveness authority.
public enum GameHistoryStore {
    public static func directory(paths: LauncherPaths) -> URL { paths.root.appendingPathComponent("records", isDirectory: true) }

    public static func databaseURL(paths: LauncherPaths) -> URL { directory(paths: paths).appendingPathComponent("records.sqlite") }
    public static func observationURLs(paths: LauncherPaths) -> [URL] { [directory(paths: paths), databaseURL(paths: paths), directory(paths: paths).appendingPathComponent("records.sqlite-wal")] }

    static func withDatabase<T>(paths: LauncherPaths, _ work: (HistoryDatabase) throws -> T) throws -> T {
        try HistoryDatabasePool.shared.database(paths: paths).synchronized(work)
    }

    static func record(_ record: GameSession, paths: LauncherPaths) throws {
        return try withDatabase(paths: paths) { db in
            try store(record, db: db)
        }
    }

    static func store(_ record: GameSession, db: HistoryDatabase) throws {
        guard record.playedSeconds.isFinite, record.playedSeconds >= 0, record.timing?.isValid != false, (record.revision) < UInt64(Int64.max) else { throw POSIXError(.EINVAL) }
        try record.validate()
        // Timing is independently updated by checkpoints; the stable context is
        // only rewritten at lifecycle transitions, never every minute.
        var snapshot = record
        snapshot.timing = nil; snapshot.controlEndpoint = nil
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 1_048_576 else { throw POSIXError(.EFBIG) }
        let started = record.timing?.startedAt ?? record.exit?.startedAt ?? record.createdAt
        try db.execute("""
            INSERT INTO sessions(id, instance_id, name, game_version, created, started, updated, seconds, played, attention, finished, revision, payload, timing, endpoint, observed)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, game_version=excluded.game_version,
                started=excluded.started, updated=excluded.updated, seconds=excluded.seconds, played=excluded.played,
                attention=excluded.attention, finished=excluded.finished, revision=excluded.revision, payload=excluded.payload, timing=excluded.timing, endpoint=excluded.endpoint, observed=excluded.observed
            WHERE (excluded.revision > sessions.revision OR (excluded.revision = sessions.revision AND
                excluded.updated > sessions.updated)) AND (sessions.finished=0 OR excluded.finished=1)
            """, [.text(record.id.uuidString), .text(record.instanceID.uuidString), .text(record.instanceName), .text(record.gameVersion),
                  .real(record.createdAt.timeIntervalSince1970), .real(started.timeIntervalSince1970), .real(record.updatedAt.timeIntervalSince1970),
                  .real(record.playedSeconds), .integer(record.hasPlayed ? 1 : 0), .integer(record.needsAttention ? 1 : 0),
                  .integer(record.state.isFinished ? 1 : 0), .integer(Int(clamping: record.revision)), .blob(data),
                  try record.timing.map { .blob(try JSONEncoder().encode($0)) } ?? .null,
                  record.state.isFinished ? .null : record.controlEndpoint.map(HistoryDatabase.Value.text) ?? .null, .real(record.updatedAt.timeIntervalSinceReferenceDate)])
    }

    public static func list(paths: LauncherPaths, query: GameHistoryQuery = .init()) throws -> [GameSession] {
        return try withDatabase(paths: paths) { db in
            var clauses: [String] = [], values: [HistoryDatabase.Value] = []
            if let id = query.instanceID { clauses.append("instance_id = ?"); values.append(.text(id.uuidString)) }
            if let date = query.since { clauses.append("started >= ?"); values.append(.real(date.timeIntervalSince1970)) }
            let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !search.isEmpty {
                clauses.append("(instr(lower(name), lower(?)) > 0 OR instr(lower(game_version), lower(?)) > 0)")
                values += [.text(search), .text(search)]
            }
            if query.problemsOnly { clauses.append("attention = 1") }
            let filter = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
            values += [.integer(max(1, min(500, query.limit))), .integer(max(0, query.offset))]
            return try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions" + filter + " ORDER BY created DESC, id DESC LIMIT ? OFFSET ?", values)
        }
    }

    public static func load(paths: LauncherPaths, sessionID: UUID) throws -> GameSession? {
        try withDatabase(paths: paths) { try $0.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE id = ?", [.text(sessionID.uuidString)]).first }
    }

    public static func summary(paths: LauncherPaths, instanceID: UUID? = nil) throws -> GameHistorySummary {
        return try withDatabase(paths: paths) { db in
            let filter = instanceID == nil ? "" : " WHERE instance_id = ?"
            let values: [HistoryDatabase.Value] = instanceID.map { [.text($0.uuidString)] } ?? []
            var result = GameHistorySummary()
            try db.rows("SELECT coalesce(sum(seconds), 0), coalesce(sum(played), 0), max(CASE WHEN played=1 THEN started END) FROM sessions" + filter, values) { stmt in
                result.seconds = sqlite3_column_double(stmt, 0)
                result.playCount = Int(sqlite3_column_int64(stmt, 1))
                if sqlite3_column_type(stmt, 2) != SQLITE_NULL { result.lastPlayed = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)) }
            }
            return result
        }
    }

    public static func days(paths: LauncherPaths, instanceID: UUID? = nil, since date: Date, calendar: Calendar = .current) throws -> [GameSessionTiming.Day] {
        return try withDatabase(paths: paths) { db in
            // updated includes checkpoint/end time, so cross-midnight runs are read.
            var values: [HistoryDatabase.Value] = [.real(date.timeIntervalSince1970)]
            if let id = instanceID { values.append(.text(id.uuidString)) }
            let records = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE updated >= ? AND played=1" + (instanceID == nil ? "" : " AND instance_id = ?"), values)
            var totals: [Date: Double] = [:]
            for record in records {
                if let timing = record.timing, !timing.days.isEmpty {
                    for day in timing.days where day.date >= date { totals[calendar.startOfDay(for: day.date), default: 0] += day.seconds }
                } else if let exit = record.exit {
                    // A result without daily segments still has a measured credit;
                    // split it over its known interval rather than putting it on day 1.
                    var cursor = max(exit.startedAt, date)
                    let end = max(exit.startedAt, exit.endedAt), wall = end.timeIntervalSince(exit.startedAt)
                    if wall <= 0 {
                        if exit.startedAt >= date { totals[calendar.startOfDay(for: exit.startedAt), default: 0] += exit.playTime }
                        continue
                    }
                    while cursor < end {
                        let day = calendar.startOfDay(for: cursor)
                        guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { break }
                        let stop = min(end, next)
                        if day >= date { totals[day, default: 0] += exit.playTime * stop.timeIntervalSince(cursor) / wall }
                        cursor = stop
                    }
                }
            }
            return totals.map { .init(date: $0.key, seconds: $0.value) }.sorted { $0.date < $1.date }
        }
    }

    static func checkpoint(_ record: GameSession, paths: LauncherPaths) throws {
        guard !record.state.isFinished, record.exit == nil, let timing = record.timing, timing.isValid else { throw POSIXError(.EINVAL) }
        try withDatabase(paths: paths) { db in
            try db.execute("""
                UPDATE sessions SET timing=?, seconds=?, started=?, played=1, updated=?, revision=?, observed=?
                WHERE id=? AND finished=0 AND revision < ?
                """, [.blob(try JSONEncoder().encode(timing)), .real(timing.awakeSeconds), .real(timing.startedAt.timeIntervalSince1970),
                      .real(record.updatedAt.timeIntervalSince1970), .integer(Int(clamping: record.revision)), .real(record.updatedAt.timeIntervalSinceReferenceDate),
                      .text(record.id.uuidString), .integer(Int(clamping: record.revision))])
        }
    }

    /// Recent detail for reconnect/recovery. Permanent history is separately paged.
    static func runtimeRecords(paths: LauncherPaths, instanceID: UUID) throws -> [GameSession] {
        try withDatabase(paths: paths) { db in
            let active = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE instance_id=? AND finished=0 ORDER BY created DESC", [.text(instanceID.uuidString)])
            let recent = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE instance_id=? AND finished=1 ORDER BY created DESC LIMIT 20", [.text(instanceID.uuidString)])
            return (active + recent).sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Retention may delete a diagnostic directory only after its latest metadata
    /// is durable. A broken/full history database therefore disables pruning.
    static func archive(_ record: GameSession, paths: LauncherPaths) throws {
        guard let saved = try load(paths: paths, sessionID: record.id), saved.isAtLeastAsRecent(as: record) else { throw POSIXError(.EIO) }
        if record.artifactState == .expired { try markArtifactsExpired(sessionID: record.id, paths: paths) }
    }
    static func markArtifactsExpired(sessionID: UUID, paths: LauncherPaths) throws {
        return try withDatabase(paths: paths) { db in
            try db.transaction {
                guard var snapshot = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE id = ?", [.text(sessionID.uuidString)]).first,
                      snapshot.state.isFinished else { throw POSIXError(.EINVAL) }
                snapshot.artifactState = .expired
                try db.execute("UPDATE sessions SET payload = ? WHERE id = ?", [.blob(try JSONEncoder().encode(snapshot)), .text(sessionID.uuidString)])
            }
        }
    }
}
