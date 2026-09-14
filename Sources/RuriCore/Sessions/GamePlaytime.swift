import RuriLocalization
import Foundation

public struct GamePlaytime: Codable, Sendable {
    var base: Double
    var sessions: [String: Double]
    public var lastPlayed: Date
    public var total: Double { base + sessions.values.reduce(0, +) }
}
public enum GamePlaytimeStore {
    public static func load(paths: LauncherPaths, instanceID: UUID) throws -> GamePlaytime? {
        let file = try LauncherPaths.safePath("playtime.json", within: paths.instance(instanceID))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attributes.isRegularFile == true, (attributes.fileSize ?? .max) <= 8_388_608 else { throw RuriError.message(Messages.CoreGamePlaytime.invalidPlaytimeRecord) }
        let record = try JSONDecoder().decode(GamePlaytime.self, from: Data(contentsOf: file))
        guard record.base.isFinite, record.base >= 0, record.sessions.count <= 100_000,
              record.sessions.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value.isFinite && $0.value >= 0 }) else { throw RuriError.message(Messages.CoreGamePlaytime.invalidPlaytimeRecord) }
        return record
    }
    /// Called by the session owner while holding the instance run lease.
    static func record(_ session: GameSession, paths: LauncherPaths) throws {
        guard let exit = session.exit else { return }
        var record = try load(paths: paths, instanceID: session.instanceID) ?? GamePlaytime(base: max(0, session.baselinePlayTime ?? 0), sessions: [:], lastPlayed: exit.startedAt)
        guard record.sessions[session.id.uuidString] == nil else { return }
        record.sessions[session.id.uuidString] = exit.playTime
        record.lastPlayed = max(record.lastPlayed, exit.startedAt)
        try JSONEncoder().encode(record).write(to: paths.instance(session.instanceID).appendingPathComponent("playtime.json"), options: .atomic)
    }
    /// Retired sessions can no longer be recovered/replayed. Fold their credit
    /// into the base so the ledger does not grow for the lifetime of an instance.
    static func compact(paths: LauncherPaths, instanceID: UUID, removing sessions: Set<UUID>) throws {
        guard !sessions.isEmpty, var record = try load(paths: paths, instanceID: instanceID) else { return }
        var changed = false
        for id in sessions {
            if let duration = record.sessions.removeValue(forKey: id.uuidString) { record.base += duration; changed = true }
        }
        if changed { try JSONEncoder().encode(record).write(to: paths.instance(instanceID).appendingPathComponent("playtime.json"), options: .atomic) }
    }
}

/// Keeps a bounded preview while reading only bytes appended since the previous
/// update. A reopened GUI starts at the tail without losing concurrently written bytes.
public actor GameSessionLogCursor {
    private let handle: FileHandle
    private var pending = Data()
    public private(set) var lines: [String] = []
    public private(set) var updates: [String] = []
    public init(paths: LauncherPaths, session: GameSession) throws {
        let url = try GameSessionStore.logURL(paths: paths, session: session)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw RuriError.message(Messages.CoreGamePlaytime.logNotRegularFile) }
        handle = try FileHandle(forReadingFrom: url)
        let length = try handle.seekToEnd(), limit: UInt64 = 2_097_152
        let offset = length > limit ? length - limit : 0
        try handle.seek(toOffset: offset)
        let data = try handle.read(upToCount: Int(length - offset)) ?? Data()
        if offset > 0, let newline = data.firstIndex(of: 10) { pending.append(data[data.index(after: newline)...]) }
        else if offset == 0 { pending.append(data) }
    }
    deinit { try? handle.close() }
    @discardableResult public func refresh(final: Bool = false) throws -> Bool {
        let offset = try handle.offset(), end = try handle.seekToEnd()
        if end < offset {
            try handle.seek(toOffset: 0); pending.removeAll(); lines.removeAll(); updates.removeAll()
        } else { try handle.seek(toOffset: offset) }
        let data = try handle.read(upToCount: 262_144) ?? Data()
        pending.append(data)
        // A final drain may require several calls; never flush a partial UTF-8
        // line while unread bytes remain in the file.
        return consume(final: final && data.isEmpty) || !data.isEmpty
    }
    private func consume(final: Bool) -> Bool {
        var added: [String] = []
        while let newline = pending.firstIndex(of: 10) {
            added.append(String(decoding: pending[..<newline], as: UTF8.self)); pending.removeSubrange(...newline)
        }
        if final && !pending.isEmpty { added.append(String(decoding: pending, as: UTF8.self)); pending.removeAll() }
        if pending.count > 2_097_152 { pending.removeAll(); added.append(Messages.CoreGamePlaytime.longLogLineOmitted.localized) }
        updates = added
        guard !added.isEmpty else { return false }
        lines += added
        if lines.count > 5000 { lines.removeFirst(lines.count - 5000) }
        var size = 0, keep = 0
        for line in lines.reversed() {
            size += line.utf8.count + 1
            if size > 2_097_152 { break }
            keep += 1
        }
        if keep < lines.count { lines.removeFirst(lines.count - keep) }
        return true
    }
}
