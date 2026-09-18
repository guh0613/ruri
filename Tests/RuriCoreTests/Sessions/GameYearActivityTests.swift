import Foundation
import Testing
@testable import RuriCore

struct GameYearActivityTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.firstWeekday = 2
        return value
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    @Test func aggregatesDuplicateCreditAndKeepsFutureDaysUnlit() {
        let result = GameYearActivity(year: 2025, dailyCredit: [
            .init(date: date("2025-01-01T00:00:00Z"), seconds: 600),
            .init(date: date("2025-01-01T03:00:00Z"), seconds: 300),
            .init(date: date("2025-01-03T00:00:00Z"), seconds: 1200),
            .init(date: date("2024-12-31T00:00:00Z"), seconds: 9000),
            .init(date: date("2026-01-01T00:00:00Z"), seconds: 9000),
            .init(date: date("2025-01-05T00:00:00Z"), seconds: 9000)
        ], calendar: calendar, now: date("2025-01-04T12:00:00Z"))
        #expect(result.seconds == 2100 && result.activeDays == 2)
        #expect(result.days.prefix(4).map(\.seconds) == [900, 0, 1200, 0])
        #expect(result.days.prefix(4).map(\.cumulativeSeconds) == [900, 900, 2100, 2100])
        #expect(result.days.dropFirst(4).allSatisfy { $0.isFuture && $0.seconds == 0 && $0.cumulativeSeconds == 0 })
        #expect(result.weeks.first?.seconds == 2100 && result.weeks.first?.activeDays == 2)
        #expect(result.weeks.dropFirst().allSatisfy { $0.isFuture })
    }

    @Test func weeklyGroupingFollowsTheCalendarsFirstWeekday() {
        let credit: [GameSessionTiming.Day] = [
            .init(date: date("2025-01-05T00:00:00Z"), seconds: 120),
            .init(date: date("2025-01-06T00:00:00Z"), seconds: 180)
        ]
        let now = date("2026-01-01T00:00:00Z")
        let monday = GameYearActivity(year: 2025, dailyCredit: credit, calendar: calendar, now: now)
        #expect(monday.weeks[0].seconds == 120 && monday.weeks[1].seconds == 180)
        var sundayCalendar = calendar; sundayCalendar.firstWeekday = 1
        let sunday = GameYearActivity(year: 2025, dailyCredit: credit, calendar: sundayCalendar, now: now)
        #expect(sunday.weeks[0].seconds == 0 && sunday.weeks[1].seconds == 300)
        #expect(sunday.weeks.reduce(0) { $0 + $1.seconds } == sunday.seconds)
        #expect(sunday.weeks.flatMap(\.days).map(\.date) == sunday.days.map(\.date))
    }

    @Test func storeClipsLegacySessionsAtBothYearBoundariesWithoutTruncatingTheYear() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try GameHistoryStore.record(session(instance, start: "2023-12-31T23:30:00Z", seconds: 3600), paths: paths)
        try GameHistoryStore.record(session(instance, start: "2024-02-29T12:00:00Z", seconds: 60), paths: paths)
        try GameHistoryStore.record(session(instance, start: "2024-12-31T23:30:00Z", seconds: 3600), paths: paths)
        try GameHistoryStore.record(session(instance, start: "2025-02-01T00:00:00Z", seconds: 9000), paths: paths)
        let result = try GameHistoryStore.yearActivity(paths: paths, year: 2024, calendar: calendar, now: date("2025-03-01T00:00:00Z"))
        #expect(result.firstRecordedYear == 2023)
        #expect(result.days.count == 366 && result.activeDays == 3)
        #expect(result.days.first?.seconds == 1800 && result.days.last?.seconds == 1800)
        #expect(result.seconds == 3660 && result.days.last?.cumulativeSeconds == 3660)
        let bounded = try GameHistoryStore.days(paths: paths, since: date("2024-01-01T00:00:00Z"), before: date("2025-01-01T00:00:00Z"), calendar: calendar)
        #expect(bounded.reduce(0) { $0 + $1.seconds } == result.seconds)
        let unbounded = try GameHistoryStore.days(paths: paths, since: date("2024-01-01T00:00:00Z"), calendar: calendar)
        #expect(unbounded.reduce(0) { $0 + $1.seconds } == result.seconds + 1800 + 9000)
    }

    @Test func storeUsesMeasuredDailyCreditAcrossInstancesIncludingInterruptedRuns() throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var measured = session(instance, start: "2024-12-31T23:00:00Z", seconds: 7200)
        measured.exit = nil
        measured.state = .interrupted
        measured.timing = .init(version: 1, startedAt: measured.createdAt, observedAt: measured.updatedAt,
                                awakeSeconds: 2400, elapsedSeconds: 7200, quality: .interrupted,
                                timeZoneIdentifier: "GMT", days: [
                                    .init(date: date("2024-12-31T00:00:00Z"), seconds: 600),
                                    .init(date: date("2025-01-01T00:00:00Z"), seconds: 1800)
                                ])
        try GameHistoryStore.record(measured, paths: paths)
        let other = session(instance, start: "2025-01-02T12:00:00Z", seconds: 120, instanceID: UUID())
        try GameHistoryStore.record(other, paths: paths)
        let result = try GameHistoryStore.yearActivity(paths: paths, year: 2025, calendar: calendar, now: date("2025-02-01T00:00:00Z"))
        #expect(result.seconds == 1920 && result.activeDays == 2)
        #expect(result.days.first?.seconds == 1800)
    }

    private func session(_ instance: GameInstance, start: String, seconds: Double, instanceID: UUID? = nil) -> GameSession {
        let started = date(start)
        var record = GameSession(id: UUID(), instanceID: instanceID ?? instance.id, instanceName: instance.name,
                                 gameVersion: instance.gameVersion, loader: "vanilla", loaderVersion: nil,
                                 memoryMB: 1024, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 123,
                                 createdAt: started, updatedAt: started.addingTimeInterval(seconds), state: .succeeded, stage: .finished, events: [], evidence: [])
        record.exit = .init(status: 0, reason: .exit, processID: 123, startedAt: started,
                            endedAt: started.addingTimeInterval(seconds), stopRequested: false, durationSeconds: seconds)
        return record
    }
}
