import Foundation
import CSQLite

public struct ServerPlaySummary: Identifiable, Sendable {
    public var id: String { address.key }
    public let address: ServerAddress
    public let name: String
    public let seconds: Double
    public let estimatedSeconds: Double
    public let visits: Int
    public let lastPlayed: Date
    public let lastInstanceID: UUID?
    public let instanceIDs: [UUID]
}

public struct GameActivityVisit: Identifiable, Sendable {
    public var id: UUID { segment.id }
    public let sessionID: UUID
    public let instanceID: UUID
    public let instanceName: String
    public let segment: GameActivitySegment
}

public enum GameActivityStore {
    static func store(_ record: GameSession, db: HistoryDatabase) throws {
        guard let activity = record.activity else { return }
        let session = record.id.uuidString
        try db.execute("DELETE FROM activity_days WHERE segment_id IN (SELECT id FROM activity_segments WHERE session_id=?)", [.text(session)])
        try db.execute("DELETE FROM activity_segments WHERE session_id=?", [.text(session)])
        for segment in activity.segments {
            try db.execute("""
                INSERT INTO activity_segments(id,session_id,instance_id,kind,target,name,started,ended,seconds,quality,payload)
                VALUES(?,?,?,?,?,?,?,?,?,?,?)
                """, [.text(segment.id.uuidString), .text(session), .text(record.instanceID.uuidString), .text(segment.target.kind), .text(segment.target.key),
                      .text(segment.target.name), .real(segment.startedAt.timeIntervalSince1970), .real(segment.endedAt.timeIntervalSince1970),
                      .real(segment.seconds), .text(segment.quality.rawValue), .blob(try JSONEncoder().encode(segment))])
            for day in segment.days {
                try db.execute("INSERT INTO activity_days(segment_id,date,seconds) VALUES(?,?,?)", [.text(segment.id.uuidString), .real(day.date.timeIntervalSince1970), .real(day.seconds)])
            }
        }
    }
    public static func servers(paths: LauncherPaths, instanceID: UUID? = nil, since: Date? = nil) throws -> [ServerPlaySummary] {
        guard FileManager.default.fileExists(atPath: GameHistoryStore.databaseURL(paths: paths).path) else { return [] }
        return try GameHistoryStore.withDatabase(paths: paths) { db in
            var clauses = ["kind='server'"], values: [HistoryDatabase.Value] = []
            if let instanceID { clauses.append("instance_id=?"); values.append(.text(instanceID.uuidString)) }
            if let since { clauses.append("started>=?"); values.append(.real(since.timeIntervalSince1970)) }
            var result: [ServerPlaySummary] = []
            try db.rows("""
                SELECT target,name,sum(seconds),sum(CASE WHEN quality!='observed' THEN seconds ELSE 0 END),count(*),max(started),instance_id,group_concat(DISTINCT instance_id)
                FROM activity_segments WHERE \(clauses.joined(separator: " AND ")) GROUP BY target ORDER BY max(started) DESC
                """, values) { row in
                guard let key = HistoryDatabase.text(row, 0), let address = try? ServerAddress(key) else { return }
                result.append(.init(address: address, name: HistoryDatabase.text(row, 1) ?? address.authority, seconds: sqlite3_column_double(row, 2),
                                    estimatedSeconds: sqlite3_column_double(row, 3), visits: Int(sqlite3_column_int64(row, 4)),
                                    lastPlayed: Date(timeIntervalSince1970: sqlite3_column_double(row, 5)), lastInstanceID: HistoryDatabase.text(row, 6).flatMap(UUID.init(uuidString:)), instanceIDs: (HistoryDatabase.text(row, 7) ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }))
            }
            return result
        }
    }
    public static func visits(paths: LauncherPaths, server: ServerAddress, instanceID: UUID? = nil, limit: Int = 50, offset: Int = 0) throws -> [GameActivityVisit] {
        guard FileManager.default.fileExists(atPath: GameHistoryStore.databaseURL(paths: paths).path) else { return [] }
        return try GameHistoryStore.withDatabase(paths: paths) { db in
            var clauses = ["a.kind='server'", "a.target=?"], values: [HistoryDatabase.Value] = [.text(server.key)]
            if let instanceID { clauses.append("a.instance_id=?"); values.append(.text(instanceID.uuidString)) }
            values += [.integer(max(1, min(500, limit))), .integer(max(0, offset))]
            var result: [GameActivityVisit] = []
            try db.rows("""
                SELECT a.payload,a.session_id,a.instance_id,s.name FROM activity_segments a JOIN sessions s ON s.id=a.session_id
                WHERE \(clauses.joined(separator: " AND ")) ORDER BY a.started DESC,a.id LIMIT ? OFFSET ?
                """, values) { row in
                guard let data = HistoryDatabase.data(row, 0), let session = HistoryDatabase.text(row, 1).flatMap(UUID.init(uuidString:)),
                      let instance = HistoryDatabase.text(row, 2).flatMap(UUID.init(uuidString:)) else { return }
                result.append(.init(sessionID: session, instanceID: instance, instanceName: HistoryDatabase.text(row, 3) ?? "", segment: try JSONDecoder().decode(GameActivitySegment.self, from: data)))
            }
            return result
        }
    }
    public static func days(paths: LauncherPaths, server: ServerAddress, instanceID: UUID? = nil, since: Date? = nil) throws -> [GameSessionTiming.Day] {
        guard FileManager.default.fileExists(atPath: GameHistoryStore.databaseURL(paths: paths).path) else { return [] }
        return try GameHistoryStore.withDatabase(paths: paths) { db in
            var clauses = ["a.kind='server'", "a.target=?"], values: [HistoryDatabase.Value] = [.text(server.key)]
            if let instanceID { clauses.append("a.instance_id=?"); values.append(.text(instanceID.uuidString)) }
            if let since { clauses.append("d.date>=?"); values.append(.real(since.timeIntervalSince1970)) }
            var result: [GameSessionTiming.Day] = []
            try db.rows("SELECT d.date,sum(d.seconds) FROM activity_days d JOIN activity_segments a ON a.id=d.segment_id WHERE \(clauses.joined(separator: " AND ")) GROUP BY d.date ORDER BY d.date", values) { row in
                result.append(.init(date: Date(timeIntervalSince1970: sqlite3_column_double(row, 0)), seconds: sqlite3_column_double(row, 1)))
            }
            return result
        }
    }
    static func worldTotals(db: HistoryDatabase, instanceID: UUID?, since: Date?) throws -> [GameHistoryTotal] {
        var clauses = ["a.kind='world'"], values: [HistoryDatabase.Value] = []
        if let instanceID { clauses.append("a.instance_id=?"); values.append(.text(instanceID.uuidString)) }
        if let since { clauses.append("a.started>=?"); values.append(.real(since.timeIntervalSince1970)) }
        var result: [GameHistoryTotal] = []
        try db.rows("""
            SELECT a.target,a.name,a.instance_id,s.name,sum(a.seconds),count(DISTINCT a.session_id),max(a.started)
            FROM activity_segments a JOIN sessions s ON s.id=a.session_id
            WHERE \(clauses.joined(separator: " AND ")) GROUP BY a.instance_id,a.target
            """, values) { row in
            guard let folder = HistoryDatabase.text(row, 0), let instance = HistoryDatabase.text(row, 2) else { return }
            result.append(.init(id: instance + "/" + folder, instanceID: UUID(uuidString: instance), folder: folder,
                                title: HistoryDatabase.text(row, 1) ?? folder, subtitle: HistoryDatabase.text(row, 3), seconds: sqlite3_column_double(row, 4),
                                count: Int(sqlite3_column_int64(row, 5)), lastPlayed: Date(timeIntervalSince1970: sqlite3_column_double(row, 6))))
        }
        return result
    }
}
