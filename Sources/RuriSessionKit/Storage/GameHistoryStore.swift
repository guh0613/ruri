import Foundation
import RuriLocalization

public enum GameHistoryStore {
    public static func directory(paths: any SessionPaths) -> URL { paths.root.appendingPathComponent("records", isDirectory: true) }

    public static func databaseURL(paths: any SessionPaths) -> URL { directory(paths: paths).appendingPathComponent("records.sqlite") }
    public static func observationURLs(paths: any SessionPaths) -> [URL] { [directory(paths: paths), databaseURL(paths: paths), directory(paths: paths).appendingPathComponent("records.sqlite-wal")] }

    package static func withDatabase<T>(paths: any SessionPaths, _ work: (HistoryDatabase) throws -> T) throws -> T {
        try HistoryDatabasePool.shared.database(paths: paths).synchronized(work)
    }

    package static func record(_ record: GameSession, paths: any SessionPaths) throws {
        return try withDatabase(paths: paths) { db in
            try store(record, db: db)
        }
    }

    package static func store(_ record: GameSession, db: HistoryDatabase) throws {
        guard record.playedSeconds.isFinite, record.playedSeconds >= 0, record.timing?.isValid != false, (record.revision) < UInt64(Int64.max) else { throw POSIXError(.EINVAL) }
        try record.validate()
        // Timing is independently updated by checkpoints; the stable context is
        // only rewritten at lifecycle transitions, never every minute.
        var snapshot = record
        snapshot.timing = nil; snapshot.controlEndpoint = nil
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 1_048_576 else { throw POSIXError(.EFBIG) }
        let started = record.timing?.startedAt ?? record.exit?.startedAt ?? record.createdAt
        try db.transaction {
        try db.execute("""
            INSERT INTO sessions(id, instance_id, name, game_version, created, started, updated, seconds, played, attention, finished, revision, payload, timing, endpoint, observed, world_folder, world_name, tracking_version)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET name=excluded.name, game_version=excluded.game_version,
                started=excluded.started, updated=excluded.updated, seconds=excluded.seconds, played=excluded.played,
                attention=excluded.attention, finished=excluded.finished, revision=excluded.revision, payload=excluded.payload, timing=excluded.timing, endpoint=excluded.endpoint, observed=excluded.observed,
                world_folder=excluded.world_folder, world_name=excluded.world_name, tracking_version=excluded.tracking_version
            WHERE (excluded.revision > sessions.revision OR (excluded.revision = sessions.revision AND
                excluded.updated > sessions.updated)) AND (sessions.finished=0 OR excluded.finished=1)
            """, [.text(record.id.uuidString), .text(record.instanceID.uuidString), .text(record.instanceName), .text(record.gameVersion),
                  .real(record.createdAt.timeIntervalSince1970), .real(started.timeIntervalSince1970), .real(record.updatedAt.timeIntervalSince1970),
                  .real(record.playedSeconds), .integer(record.hasPlayed ? 1 : 0), .integer(record.needsAttention ? 1 : 0),
                  .integer(record.state.isFinished ? 1 : 0), .integer(Int(clamping: record.revision)), .blob(data),
                  try record.timing.map { .blob(try JSONEncoder().encode($0)) } ?? .null,
                  record.state.isFinished ? .null : record.controlEndpoint.map(HistoryDatabase.Value.text) ?? .null, .real(record.updatedAt.timeIntervalSinceReferenceDate),
                  record.world.map { HistoryDatabase.Value.text($0.folder) } ?? .null, record.world.map { HistoryDatabase.Value.text($0.name) } ?? .null, record.activity.map { .integer($0.version) } ?? .null])
        if try db.scalar("SELECT changes()") > 0 { try GameActivityStore.store(record, db: db) }
        }
    }

    public static func load(paths: any SessionPaths, sessionID: UUID) throws -> GameSession? {
        try withDatabase(paths: paths) { try $0.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE id = ?", [.text(sessionID.uuidString)]).first }
    }

    package static func checkpoint(_ record: GameSession, paths: any SessionPaths) throws {
        guard !record.state.isFinished, record.exit == nil, let timing = record.timing, timing.isValid else { throw POSIXError(.EINVAL) }
        if record.activity != nil { try Self.record(record, paths: paths); return }
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
    package static func runtimeRecords(paths: any SessionPaths, instanceID: UUID) throws -> [GameSession] {
        try withDatabase(paths: paths) { db in
            let active = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE instance_id=? AND finished=0 ORDER BY created DESC", [.text(instanceID.uuidString)])
            let recent = try db.records("SELECT payload, timing, updated, revision, endpoint, observed FROM sessions WHERE instance_id=? AND finished=1 ORDER BY created DESC LIMIT 20", [.text(instanceID.uuidString)])
            return (active + recent).sorted { $0.createdAt > $1.createdAt }
        }
    }

    /// Retention may delete a diagnostic directory only after its latest metadata
    /// is durable. A broken/full history database therefore disables pruning.
    package static func archive(_ record: GameSession, paths: any SessionPaths) throws {
        guard let saved = try load(paths: paths, sessionID: record.id), saved.isAtLeastAsRecent(as: record) else { throw POSIXError(.EIO) }
        if record.artifactState == .expired { try markArtifactsExpired(sessionID: record.id, paths: paths) }
    }
    package static func markArtifactsExpired(sessionID: UUID, paths: any SessionPaths) throws {
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
