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
    public var worldFolder: String?
    public var since: Date?
    public var search: String
    public var problemsOnly: Bool
    public var limit: Int
    public var offset: Int
    public init(instanceID: UUID? = nil, worldFolder: String? = nil, since: Date? = nil, search: String = "", problemsOnly: Bool = false, limit: Int = 100, offset: Int = 0) {
        self.instanceID = instanceID; self.worldFolder = worldFolder; self.since = since; self.search = search
        self.problemsOnly = problemsOnly; self.limit = limit; self.offset = offset
    }
}

/// One column of the activity chart: a day or a month, already zero-filled so
/// a quiet stretch reads as a gap rather than disappearing from the axis.
public struct GameHistoryBucket: Identifiable, Sendable {
    public let date: Date
    public var seconds: Double
    public var count: Int
    public var id: Date { date }
    public init(date: Date, seconds: Double, count: Int) { self.date = date; self.seconds = seconds; self.count = count }
}

/// A grouped row of the retrospective: one instance, or one save.
public struct GameHistoryTotal: Identifiable, Sendable {
    public let id: String
    public let instanceID: UUID?
    /// The save folder, for a world row; `nil` for an instance row.
    public let folder: String?
    public let title: String
    public let subtitle: String?
    public let seconds: Double
    public let count: Int
    public let lastPlayed: Date?
}

public enum GameHistoryRange: Hashable, Sendable {
    case days(Int), months(Int), all
    var usesDailyBuckets: Bool { if case .days = self { true } else { false } }
}

/// Everything the history page shows above its timeline, read in one pass.
public struct GameHistoryOverview: Sendable {
    public var seconds = 0.0
    public var playCount = 0
    public var longestSeconds = 0.0
    public var activeDays = 0
    public var streakDays = 0
    public var firstPlayed: Date?
    public var lastPlayed: Date?
    public var buckets: [GameHistoryBucket] = []
    public var daily = true
    public var instances: [GameHistoryTotal] = []
    public var worlds: [GameHistoryTotal] = []
    /// The total for the stretch of the same length just before this one, so
    /// the page can say whether play went up or down; `nil` for all time.
    public var previousSeconds: Double?
    /// The single longest run in the range.
    public var longest: GameSession?
    /// The days with any play among the last seven, whatever the range.
    public var recentDays: Set<Date> = []
    public var averageSeconds: Double { playCount > 0 ? seconds / Double(playCount) : 0 }
    public init() {}
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
            INSERT INTO sessions(id, instance_id, name, game_version, created, started, updated, seconds, played, attention, finished, revision, payload, timing, endpoint, observed, world_folder, world_name)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, game_version=excluded.game_version,
                started=excluded.started, updated=excluded.updated, seconds=excluded.seconds, played=excluded.played,
                attention=excluded.attention, finished=excluded.finished, revision=excluded.revision, payload=excluded.payload, timing=excluded.timing, endpoint=excluded.endpoint, observed=excluded.observed,
                world_folder=excluded.world_folder, world_name=excluded.world_name
            WHERE (excluded.revision > sessions.revision OR (excluded.revision = sessions.revision AND
                excluded.updated > sessions.updated)) AND (sessions.finished=0 OR excluded.finished=1)
            """, [.text(record.id.uuidString), .text(record.instanceID.uuidString), .text(record.instanceName), .text(record.gameVersion),
                  .real(record.createdAt.timeIntervalSince1970), .real(started.timeIntervalSince1970), .real(record.updatedAt.timeIntervalSince1970),
                  .real(record.playedSeconds), .integer(record.hasPlayed ? 1 : 0), .integer(record.needsAttention ? 1 : 0),
                  .integer(record.state.isFinished ? 1 : 0), .integer(Int(clamping: record.revision)), .blob(data),
                  try record.timing.map { .blob(try JSONEncoder().encode($0)) } ?? .null,
                  record.state.isFinished ? .null : record.controlEndpoint.map(HistoryDatabase.Value.text) ?? .null, .real(record.updatedAt.timeIntervalSinceReferenceDate),
                  record.world.map { HistoryDatabase.Value.text($0.folder) } ?? .null, record.world.map { HistoryDatabase.Value.text($0.name) } ?? .null])
    }

    public static func list(paths: LauncherPaths, query: GameHistoryQuery = .init()) throws -> [GameSession] {
        return try withDatabase(paths: paths) { db in
            var clauses: [String] = [], values: [HistoryDatabase.Value] = []
            if let id = query.instanceID { clauses.append("instance_id = ?"); values.append(.text(id.uuidString)) }
            if let folder = query.worldFolder { clauses.append("world_folder = ?"); values.append(.text(folder)) }
            if let date = query.since { clauses.append("started >= ?"); values.append(.real(date.timeIntervalSince1970)) }
            let search = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
            if !search.isEmpty {
                clauses.append("(instr(lower(name), lower(?)) > 0 OR instr(lower(game_version), lower(?)) > 0 OR instr(lower(coalesce(world_name, '')), lower(?)) > 0)")
                values += [.text(search), .text(search), .text(search)]
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

    // MARK: Retrospective

    /// The numbers, the activity series and the groupings behind the history
    /// page, read under one lock so the page never shows a half-updated set.
    public static func overview(paths: LauncherPaths, instanceID: UUID? = nil, range: GameHistoryRange = .days(30),
                                calendar: Calendar = .current, now: Date = Date()) throws -> GameHistoryOverview {
        let start = rangeStart(range, calendar: calendar, now: now)
        return try withDatabase(paths: paths) { db in
            var result = GameHistoryOverview()
            result.daily = range.usesDailyBuckets
            var clauses = ["played = 1"], values: [HistoryDatabase.Value] = []
            if let instanceID { clauses.append("instance_id = ?"); values.append(.text(instanceID.uuidString)) }
            let baseClauses = clauses, baseValues = values
            if let start { clauses.append("started >= ?"); values.append(.real(start.timeIntervalSince1970)) }
            let filter = " WHERE " + clauses.joined(separator: " AND ")
            if let start, let previousStart = previousRangeStart(range, start: start, calendar: calendar) {
                let previousFilter = " WHERE " + (baseClauses + ["started >= ?", "started < ?"]).joined(separator: " AND ")
                try db.rows("SELECT coalesce(sum(seconds), 0) FROM sessions" + previousFilter,
                            baseValues + [.real(previousStart.timeIntervalSince1970), .real(start.timeIntervalSince1970)]) { statement in
                    result.previousSeconds = sqlite3_column_double(statement, 0)
                }
            }
            result.longest = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions\(filter) ORDER BY seconds DESC LIMIT 1", values).first
            try db.rows("""
                SELECT coalesce(sum(seconds), 0), count(*), coalesce(max(seconds), 0), max(started), min(started),
                       count(DISTINCT strftime('%Y-%m-%d', started, 'unixepoch', 'localtime')) FROM sessions\(filter)
                """, values) { statement in
                result.seconds = sqlite3_column_double(statement, 0)
                result.playCount = Int(sqlite3_column_int64(statement, 1))
                result.longestSeconds = sqlite3_column_double(statement, 2)
                if sqlite3_column_type(statement, 3) != SQLITE_NULL { result.lastPlayed = Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)) }
                if sqlite3_column_type(statement, 4) != SQLITE_NULL { result.firstPlayed = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4)) }
                result.activeDays = Int(sqlite3_column_int64(statement, 5))
            }
            try db.rows("""
                SELECT instance_id, name, sum(seconds), count(*), max(started) FROM sessions\(filter)
                GROUP BY instance_id ORDER BY 3 DESC LIMIT 16
                """, values) { statement in
                guard let id = HistoryDatabase.text(statement, 0) else { return }
                result.instances.append(.init(id: id, instanceID: UUID(uuidString: id), folder: nil, title: HistoryDatabase.text(statement, 1) ?? id,
                                              subtitle: nil, seconds: sqlite3_column_double(statement, 2), count: Int(sqlite3_column_int64(statement, 3)),
                                              lastPlayed: Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))))
            }
            try db.rows("""
                SELECT world_folder, world_name, instance_id, name, sum(seconds), count(*), max(started) FROM sessions\(filter)
                AND world_folder IS NOT NULL GROUP BY instance_id, world_folder ORDER BY 5 DESC LIMIT 16
                """, values) { statement in
                guard let folder = HistoryDatabase.text(statement, 0), let instance = HistoryDatabase.text(statement, 2) else { return }
                result.worlds.append(.init(id: instance + "/" + folder, instanceID: UUID(uuidString: instance), folder: folder,
                                           title: HistoryDatabase.text(statement, 1) ?? folder, subtitle: HistoryDatabase.text(statement, 3),
                                           seconds: sqlite3_column_double(statement, 4), count: Int(sqlite3_column_int64(statement, 5)),
                                           lastPlayed: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))))
            }
            var counts: [Date: Int] = [:]
            let unit = range.usesDailyBuckets ? "%Y-%m-%d" : "%Y-%m"
            try db.rows("SELECT strftime(?, started, 'unixepoch', 'localtime'), sum(seconds), count(*) FROM sessions\(filter) GROUP BY 1",
                        [.text(unit)] + values) { statement in
                guard let key = HistoryDatabase.text(statement, 0), let date = Self.date(key, calendar: calendar) else { return }
                counts[date] = Int(sqlite3_column_int64(statement, 2))
                // Monthly columns come from the start stamp; the daily series is
                // replaced below by measured per-day credit, which splits runs
                // that cross midnight instead of banking them on day one.
                if !range.usesDailyBuckets { result.buckets.append(.init(date: date, seconds: sqlite3_column_double(statement, 1), count: counts[date] ?? 0)) }
            }
            if range.usesDailyBuckets, let start {
                for day in try days(paths: paths, instanceID: instanceID, since: start, calendar: calendar) {
                    result.buckets.append(.init(date: calendar.startOfDay(for: day.date), seconds: day.seconds, count: 0))
                }
            }
            result.buckets = fill(result.buckets, counts: counts, range: range, start: start, calendar: calendar, now: now)
            let played = try playedDays(db: db, instanceID: instanceID, calendar: calendar)
            result.streakDays = streak(played, calendar: calendar, now: now)
            if let weekAgo = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) {
                result.recentDays = played.filter { $0 >= weekAgo }
            }
            return result
        }
    }

    private static func rangeStart(_ range: GameHistoryRange, calendar: Calendar, now: Date) -> Date? {
        switch range {
        case .days(let count): return calendar.date(byAdding: .day, value: -(max(1, count) - 1), to: calendar.startOfDay(for: now))
        case .months(let count): return calendar.date(byAdding: .month, value: -(max(1, count) - 1), to: startOfMonth(now, calendar: calendar))
        case .all: return nil
        }
    }
    private static func previousRangeStart(_ range: GameHistoryRange, start: Date, calendar: Calendar) -> Date? {
        switch range {
        case .days(let count): return calendar.date(byAdding: .day, value: -max(1, count), to: start)
        case .months(let count): return calendar.date(byAdding: .month, value: -max(1, count), to: start)
        case .all: return nil
        }
    }
    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }
    /// SQLite reports local calendar keys; rebuild the matching instant rather
    /// than reparsing with a formatter whose locale could reorder the fields.
    private static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var components = DateComponents(); components.year = parts[0]; components.month = parts[1]
        if parts.count >= 3 { components.day = parts[2] }
        return calendar.date(from: components)
    }
    private static func fill(_ buckets: [GameHistoryBucket], counts: [Date: Int], range: GameHistoryRange,
                             start: Date?, calendar: Calendar, now: Date) -> [GameHistoryBucket] {
        var totals: [Date: Double] = [:]
        for bucket in buckets { totals[bucket.date, default: 0] += bucket.seconds }
        let component: Calendar.Component = range.usesDailyBuckets ? .day : .month
        var cursor = start ?? totals.keys.min() ?? counts.keys.min() ?? startOfMonth(now, calendar: calendar)
        cursor = range.usesDailyBuckets ? calendar.startOfDay(for: cursor) : startOfMonth(cursor, calendar: calendar)
        let end = range.usesDailyBuckets ? calendar.startOfDay(for: now) : startOfMonth(now, calendar: calendar)
        var result: [GameHistoryBucket] = []
        while cursor <= end, result.count < 400 {
            result.append(.init(date: cursor, seconds: totals[cursor] ?? 0, count: counts[cursor] ?? 0))
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        // A very long history is shown by its most recent columns; the totals
        // above still describe the whole range.
        return result.count > 120 ? Array(result.suffix(120)) : result
    }
    /// The most recent days with any play, independent of the chosen range.
    private static func playedDays(db: HistoryDatabase, instanceID: UUID?, calendar: Calendar) throws -> Set<Date> {
        var values: [HistoryDatabase.Value] = []
        var filter = " WHERE played = 1"
        if let instanceID { filter += " AND instance_id = ?"; values.append(.text(instanceID.uuidString)) }
        var played = Set<Date>()
        try db.rows("SELECT DISTINCT strftime('%Y-%m-%d', started, 'unixepoch', 'localtime') FROM sessions\(filter) ORDER BY 1 DESC LIMIT 400", values) { statement in
            if let key = HistoryDatabase.text(statement, 0), let date = Self.date(key, calendar: calendar) { played.insert(date) }
        }
        return played
    }
    private static func streak(_ played: Set<Date>, calendar: Calendar, now: Date) -> Int {
        let today = calendar.startOfDay(for: now)
        guard var cursor = played.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var count = 0
        while played.contains(cursor), count < 400 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor), previous < cursor else { break }
            cursor = previous
        }
        return count
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
