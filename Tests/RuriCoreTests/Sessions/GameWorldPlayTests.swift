import Foundation
import Testing
@testable import RuriCore

struct GameWorldPlayTests {
    private let builder = WorldTests()

    private func level(name: String, lastPlayed: Date?) -> Data {
        var world = builder.named(8, "LevelName", builder.string(name))
        if let lastPlayed {
            let milliseconds = Int64(lastPlayed.timeIntervalSince1970 * 1000)
            let bytes = (0..<8).map { UInt8(truncatingIfNeeded: milliseconds >> (8 * (7 - $0))) }
            world += builder.named(4, "LastPlayed", Data(bytes))
        }
        return Data([10, 0, 0]) + builder.named(10, "Data", world + Data([0])) + Data([0])
    }

    private func save(_ game: URL, folder: String, name: String, lastPlayed: Date?) throws {
        let world = game.appendingPathComponent("saves/\(folder)")
        try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
        try level(name: name, lastPlayed: lastPlayed).write(to: world.appendingPathComponent("level.dat"))
    }

    @Test func theMostRecentlyStampedSaveInsideTheRunWindowIsTheOnePlayed() throws {
        let game = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: game) }
        let start = Date(timeIntervalSince1970: 1_700_000_000), end = start.addingTimeInterval(3600)
        try save(game, folder: "old", name: "Older World", lastPlayed: start.addingTimeInterval(-7 * 86400))
        try save(game, folder: "first", name: "第一个世界", lastPlayed: start.addingTimeInterval(600))
        try save(game, folder: "second", name: "第二个世界", lastPlayed: start.addingTimeInterval(3000))
        try save(game, folder: "unstamped", name: "No Stamp", lastPlayed: nil)

        let played = try #require(GameWorldActivity.played(in: game, start: start, end: end))
        #expect(played.folder == "second" && played.name == "第二个世界" && played.source == .detected)

        // A run that ended before any save was written keeps no world at all.
        #expect(GameWorldActivity.played(in: game, start: start.addingTimeInterval(-86400), end: start.addingTimeInterval(-3600)) == nil)
    }

    @Test func aQuickPlayChoiceKeepsItsProvenanceButYieldsToWhereThePlayerEndedUp() throws {
        let game = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: game) }
        let start = Date(timeIntervalSince1970: 1_700_000_000), end = start.addingTimeInterval(1800)
        try save(game, folder: "chosen", name: "Renamed In Game", lastPlayed: start.addingTimeInterval(300))

        var record = GameSession(id: UUID(), instanceID: UUID(), instanceName: "Test", gameVersion: "1.21.1", loader: "vanilla", loaderVersion: nil,
                                 memoryMB: 2048, operatingSystem: "macOS", hostArchitecture: "aarch64", accountMode: "offline", ownerPID: 1,
                                 createdAt: start, updatedAt: end, state: .succeeded, stage: .finished, events: [], evidence: [])
        record.gameDirectory = game
        record.world = .init(folder: "chosen", name: "Stale Name", source: .quickPlay)
        record.applyWorldPlayed(start: start, end: end)
        #expect(record.world?.source == .quickPlay && record.world?.name == "Renamed In Game")
        try record.validate()

        try save(game, folder: "elsewhere", name: "Elsewhere", lastPlayed: start.addingTimeInterval(1200))
        record.applyWorldPlayed(start: start, end: end)
        #expect(record.world?.folder == "elsewhere" && record.world?.source == .detected)
    }

    @Test func recordDatabasesWrittenBeforeSavesWereTrackedMigrateAndKeepTheirRuns() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var record = GameSession(id: UUID(), instanceID: instance.id, instanceName: instance.name, gameVersion: instance.gameVersion,
                                 loader: "vanilla", loaderVersion: nil, memoryMB: 2048, operatingSystem: "macOS", hostArchitecture: "aarch64",
                                 accountMode: "offline", ownerPID: 1, createdAt: Date(), updatedAt: Date(), state: .succeeded, stage: .finished,
                                 events: [], evidence: [])
        record.exit = .init(status: 0, reason: .exit, processID: 1, startedAt: record.createdAt,
                            endedAt: record.createdAt.addingTimeInterval(300), stopRequested: false, durationSeconds: 300)
        try GameHistoryStore.record(record, paths: paths)
        // Roll the file back to the schema that had no save columns.
        try GameHistoryStore.withDatabase(paths: paths) { db in
            try db.execute("DROP INDEX sessions_world")
            try db.execute("ALTER TABLE sessions DROP COLUMN world_folder")
            try db.execute("ALTER TABLE sessions DROP COLUMN world_name")
            try db.execute("PRAGMA user_version=1")
        }
        let reopened = try HistoryDatabase(paths: paths)
        #expect(try reopened.scalar("PRAGMA user_version") == 2)

        var later = record
        later.world = .init(folder: "after", name: "After", source: .detected)
        later.revision = 5
        later.updatedAt = record.updatedAt.addingTimeInterval(60)
        try GameHistoryStore.record(later, paths: paths)
        #expect(try GameHistoryStore.load(paths: paths, sessionID: record.id)?.world?.folder == "after")
        #expect(try GameHistoryStore.overview(paths: paths, range: .all).worlds.first?.title == "After")
    }

    @Test func savesAreIndexedAndGroupedByTheHistoryOverview() throws {
        let (paths, instance) = try GameSessionTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        for (index, folder) in ["alpha", "alpha", "beta"].enumerated() {
            var record = GameSession(id: UUID(), instanceID: instance.id, instanceName: instance.name, gameVersion: instance.gameVersion,
                                     loader: "vanilla", loaderVersion: nil, memoryMB: 2048, operatingSystem: "macOS", hostArchitecture: "aarch64",
                                     accountMode: "offline", ownerPID: 1, createdAt: day.addingTimeInterval(Double(index) * 60),
                                     updatedAt: day.addingTimeInterval(Double(index) * 60 + 600), state: .succeeded, stage: .finished, events: [], evidence: [])
            record.exit = .init(status: 0, reason: .exit, processID: 1, startedAt: record.createdAt,
                                endedAt: record.createdAt.addingTimeInterval(600), stopRequested: false, durationSeconds: 600)
            record.world = .init(folder: folder, name: folder == "alpha" ? "Alpha" : "Beta", source: .detected)
            try GameHistoryStore.record(record, paths: paths)
        }
        let overview = try GameHistoryStore.overview(paths: paths, range: .days(7))
        #expect(overview.playCount == 3 && overview.seconds == 1800)
        #expect(overview.streakDays == 1 && overview.activeDays == 1)
        #expect(overview.buckets.count == 7 && overview.buckets.last?.seconds == 1800)
        #expect(overview.instances.count == 1 && overview.instances.first?.count == 3)
        #expect(overview.worlds.map(\.title) == ["Alpha", "Beta"])
        #expect(overview.worlds.first?.seconds == 1200 && overview.worlds.first?.folder == "alpha")
        #expect(try GameHistoryStore.list(paths: paths, query: .init(worldFolder: "beta")).count == 1)
        #expect(try GameHistoryStore.list(paths: paths, query: .init(search: "alph")).count == 2)
    }
}
