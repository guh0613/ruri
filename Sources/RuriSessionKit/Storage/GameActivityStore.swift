import Foundation
import RuriLocalization

public enum GameActivityStore {
    package static func store(_ record: GameSession, db: HistoryDatabase) throws {
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
}
