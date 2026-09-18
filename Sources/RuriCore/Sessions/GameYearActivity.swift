import Foundation
import CSQLite

/// Calendar-aligned activity, independent of the retrospective's capped chart
/// buckets. Only confirmed daily credit is counted, including midnight splits.
public struct GameYearActivity: Sendable {
    public struct Day: Identifiable, Sendable {
        public let date: Date
        public let column: Int
        public let row: Int
        public let seconds: Double
        public let cumulativeSeconds: Double
        public let isFuture: Bool
        public var id: Date { date }
    }

    public struct Week: Identifiable, Sendable {
        public let column: Int
        public let days: [Day]
        public var id: Int { column }
        public var seconds: Double { days.reduce(0) { $0 + $1.seconds } }
        public var activeDays: Int { days.filter { $0.seconds > 0 }.count }
        public var isFuture: Bool { days.allSatisfy(\.isFuture) }
    }

    public let year: Int
    public let firstRecordedYear: Int?
    public let days: [Day]
    public let weeks: [Week]
    public var seconds: Double { days.reduce(0) { $0 + $1.seconds } }
    public var activeDays: Int { days.filter { $0.seconds > 0 }.count }

    public init(year: Int, dailyCredit: [GameSessionTiming.Day] = [], firstRecordedYear: Int? = nil,
                calendar: Calendar = .current, now: Date = Date()) {
        self.year = year
        self.firstRecordedYear = firstRecordedYear
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            days = []; weeks = []; return
        }
        let today = calendar.startOfDay(for: now)
        var totals: [Date: Double] = [:]
        for credit in dailyCredit where credit.seconds.isFinite && credit.seconds > 0 {
            let day = calendar.startOfDay(for: credit.date)
            if day >= start, day < end, day <= today { totals[day, default: 0] += credit.seconds }
        }
        let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var cursor = start, cumulative = 0.0, result: [Day] = []
        while cursor < end {
            let seconds = totals[cursor] ?? 0
            cumulative += seconds
            let position = offset + result.count
            result.append(.init(date: cursor, column: position / 7, row: position % 7, seconds: seconds,
                                cumulativeSeconds: cursor > today ? 0 : cumulative, isFuture: cursor > today))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        days = result
        let grouped = Dictionary(grouping: result, by: \.column)
        weeks = grouped.keys.sorted().map { .init(column: $0, days: grouped[$0] ?? []) }
    }
}

extension GameHistoryStore {
    public static func yearActivity(paths: LauncherPaths, year: Int, calendar: Calendar = .current,
                                    now: Date = Date()) throws -> GameYearActivity {
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else {
            return GameYearActivity(year: year, calendar: calendar, now: now)
        }
        return try withDatabase(paths: paths) { db in
            var firstYear: Int?
            try db.rows("SELECT min(started) FROM sessions WHERE played = 1") { statement in
                if sqlite3_column_type(statement, 0) != SQLITE_NULL {
                    firstYear = calendar.component(.year, from: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)))
                }
            }
            let credit = try days(paths: paths, since: start, before: end, calendar: calendar)
            return GameYearActivity(year: year, dailyCredit: credit, firstRecordedYear: firstYear, calendar: calendar, now: now)
        }
    }
}
