import Foundation
import Darwin
import CSQLite
import RuriLocalization

/// One serialized connection per data root. A transaction cannot interleave
/// with another caller in this process; WAL coordinates other launcher/monitor
/// processes. The bounded cache also releases roots used by disposable tests.
final class HistoryDatabasePool: @unchecked Sendable {
    static let shared = HistoryDatabasePool()
    private let lock = NSLock()
    private var entries: [String: (HistoryDatabase, UInt64)] = [:]
    private var sequence: UInt64 = 0

    func database(paths: LauncherPaths) throws -> HistoryDatabase {
        lock.lock(); defer { lock.unlock() }
        let key = paths.root.standardizedFileURL.resolvingSymlinksInPath().path
        sequence &+= 1
        if let entry = entries[key], entry.0.isCurrent {
            entries[key] = (entry.0, sequence)
            return entry.0
        }
        entries.removeValue(forKey: key)
        let db = try HistoryDatabase(paths: paths)
        if entries.count >= 8, let oldest = entries.min(by: { $0.value.1 < $1.value.1 })?.key { entries.removeValue(forKey: oldest) }
        entries[key] = (db, sequence)
        return db
    }
}

final class HistoryDatabase: @unchecked Sendable {
    enum Value { case text(String), real(Double), integer(Int), blob(Data), null }
    private var connection: OpaquePointer?
    private let lock = NSRecursiveLock()
    let file: URL
    private var identity: (dev_t, ino_t)?

    func synchronized<T>(_ body: (HistoryDatabase) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(self)
    }
    var isCurrent: Bool {
        var info = stat()
        return lstat(file.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG && identity?.0 == info.st_dev && identity?.1 == info.st_ino
    }

    init(paths: LauncherPaths) throws {
        let directory = try LauncherPaths.safePath("records", within: paths.root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        file = try LauncherPaths.safePath("records.sqlite", within: directory)
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let url = directory.appendingPathComponent("records.sqlite" + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw POSIXError(.EINVAL) }
            }
        }
        // Foundation canonicalizes /private/var back to /var on macOS. SQLite's
        // NOFOLLOW flag rejects even that system symlink, so use POSIX realpath
        // for the existing parent rather than weakening the no-symlink open.
        guard let resolved = realpath(directory.path, nil) else { throw POSIXError(.ENOENT) }
        let databasePath = String(cString: resolved) + "/records.sqlite"
        free(resolved)
        let result = sqlite3_open_v2(databasePath, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW, nil)
        guard result == SQLITE_OK else { let error = failure(); sqlite3_close(connection); connection = nil; throw error }
        do {
            sqlite3_busy_timeout(connection, 1500)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let version = try scalar("PRAGMA user_version")
            guard version == 0 || version == 1 || version == 2 else { throw POSIXError(.EPROTONOSUPPORT) }
            if version == 1 {
                // The save a run was spent in became indexed metadata in v2.
                // Existing rows keep NULL; they predate the read-back.
                try transaction {
                    guard try scalar("PRAGMA user_version") == 1 else { return }
                    try execute("ALTER TABLE sessions ADD COLUMN world_folder TEXT")
                    try execute("ALTER TABLE sessions ADD COLUMN world_name TEXT")
                    try execute("CREATE INDEX sessions_world ON sessions(instance_id, world_folder, started)")
                    try execute("PRAGMA user_version=2")
                }
            }
            if version == 0 {
                var info = statfs()
                let local = statfs(directory.path, &info) == 0 && info.f_flags & UInt32(MNT_LOCAL) != 0
                try execute(local ? "PRAGMA journal_mode=WAL" : "PRAGMA journal_mode=DELETE")
                try transaction {
                    guard try scalar("PRAGMA user_version") == 0 else { return }
                    try execute("""
                        CREATE TABLE sessions(
                            id TEXT PRIMARY KEY, instance_id TEXT NOT NULL, name TEXT NOT NULL, game_version TEXT NOT NULL,
                            created REAL NOT NULL, started REAL NOT NULL, updated REAL NOT NULL, seconds REAL NOT NULL,
                            played INTEGER NOT NULL, attention INTEGER NOT NULL, finished INTEGER NOT NULL,
                            revision INTEGER NOT NULL, payload BLOB NOT NULL, timing BLOB, endpoint TEXT, observed REAL NOT NULL,
                            reviewed_revision INTEGER, reviewed_at REAL, world_folder TEXT, world_name TEXT)
                        """)
                    try execute("CREATE INDEX sessions_world ON sessions(instance_id, world_folder, started)")
                    try execute("CREATE INDEX sessions_instance_date ON sessions(instance_id, created DESC)")
                    try execute("CREATE INDEX sessions_date ON sessions(created DESC)")
                    try execute("CREATE INDEX sessions_updated ON sessions(updated)")
                    try execute("CREATE INDEX sessions_credit ON sessions(instance_id, seconds, played, started)")
                    try execute("CREATE INDEX sessions_active ON sessions(instance_id, finished, created DESC)")
                    try execute("CREATE TABLE runtime_events(id TEXT PRIMARY KEY, session_id TEXT NOT NULL, date REAL NOT NULL, payload BLOB NOT NULL)")
                    try execute("CREATE INDEX runtime_events_session ON runtime_events(session_id, date)")
                    try execute("CREATE TABLE launcher_events(id TEXT PRIMARY KEY, session_id TEXT, updated REAL NOT NULL, running INTEGER NOT NULL, payload BLOB NOT NULL)")
                    try execute("CREATE INDEX launcher_events_session ON launcher_events(session_id, updated)")
                    try execute("PRAGMA user_version=2")
                }
            }
            var info = stat()
            if lstat(file.path, &info) == 0 { identity = (info.st_dev, info.st_ino) }
            // Metadata is low frequency and must survive a power loss. Do not
            // weaken durability to make synthetic throughput numbers look better.
            try execute("PRAGMA synchronous=FULL")
        } catch { sqlite3_close(connection); connection = nil; throw error }
    }
    deinit { sqlite3_close(connection) }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try work(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    func execute(_ sql: String, _ values: [Value] = []) throws { try rows(sql, values) { _ in } }
    func scalar(_ sql: String, _ values: [Value] = []) throws -> Double {
        var value = 0.0
        try rows(sql, values) { value = sqlite3_column_double($0, 0) }
        return value
    }
    func records(_ sql: String, _ values: [Value] = []) throws -> [GameSession] {
        var records: [GameSession] = []
        try rows(sql, values) { statement in
            try Task.checkCancellation()
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, count <= 1_048_576, let bytes = sqlite3_column_blob(statement, 0) else { throw POSIXError(.EINVAL) }
            var record = try JSONDecoder().decode(GameSession.self, from: Data(bytes: bytes, count: count))
            guard sqlite3_column_count(statement) == 6, sqlite3_column_type(statement, 5) != SQLITE_NULL,
                  sqlite3_column_int64(statement, 3) >= 0 else { throw POSIXError(.EINVAL) }
            record.timing = try Self.data(statement, 1).map { try JSONDecoder().decode(GameSessionTiming.self, from: $0) }
            record.updatedAt = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 5))
            record.revision = UInt64(sqlite3_column_int64(statement, 3))
            record.controlEndpoint = record.state.isFinished ? nil : Self.text(statement, 4)
            try record.validate()
            records.append(record)
        }
        return records
    }
    static func data(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, count <= 1_048_576, let bytes = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: bytes, count: count)
    }
    static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
    func rows(_ sql: String, _ values: [Value] = [], _ consume: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let code: Int32
            switch value {
            case .null: code = sqlite3_bind_null(statement, position)
            case .text(let text): code = text.withCString { sqlite3_bind_text(statement, position, $0, -1, transient) }
            case .real(let number): code = sqlite3_bind_double(statement, position, number)
            case .integer(let number): code = sqlite3_bind_int64(statement, position, Int64(number))
            case .blob(let data): code = data.withUnsafeBytes { sqlite3_bind_blob(statement, position, $0.baseAddress, Int32($0.count), transient) }
            }
            guard code == SQLITE_OK else { throw failure() }
        }
        // Cancellation must never suppress COMMIT/ROLLBACK or final lifecycle
        // writes. Read-only record enumeration checks cancellation separately.
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try consume(statement)
            case SQLITE_DONE: return
            default: throw failure()
            }
        }
    }
    private func failure() -> RuriError {
        .message(Messages.SessionRuntime.historyError(connection.map { String(cString: sqlite3_errmsg($0)) } ?? String(SQLITE_CANTOPEN)))
    }
}
