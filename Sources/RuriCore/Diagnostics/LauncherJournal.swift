import Foundation
import RuriLocalization

public struct LauncherLogEntry: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case launcher, task, game }
    public enum Level: String, Codable, CaseIterable, Sendable { case info, success, warning, error }
    public enum Status: String, Codable, Sendable { case recorded, running, completed, failed, cancelled, interrupted }
    public struct Step: Identifiable, Codable, Equatable, Sendable {
        public let id: UUID
        public let date: Date
        public let message: LocalizedMessage
    }

    public let id: UUID
    public let startedAt: Date
    public internal(set) var updatedAt: Date
    public let kind: Kind
    public let titleMessage: LocalizedMessage
    public internal(set) var level: Level
    public internal(set) var status: Status
    public internal(set) var detailMessage: LocalizedMessage?
    public var detail: String? { detailMessage?.localized }
    public internal(set) var steps: [Step] = []
    public internal(set) var completed = 0
    public internal(set) var total = 0
    public internal(set) var isNotification: Bool
    public internal(set) var isRead: Bool
    public internal(set) var sessionID: UUID?
    public internal(set) var fileURL: URL?
    public var title: String { titleMessage.localized }
    public var progress: InstallProgress {
        InstallProgress(steps.last?.message ?? Messages.AppActivityItem.preparing, completed: completed, total: total)
    }
    public var needsAttention: Bool { level == .warning || level == .error }
}

/// One bounded history backs both the launcher log and its notification inbox.
/// High frequency progress replaces counters; only stage changes add a step.
public struct LauncherJournal: Codable, Sendable {
    public static let capacity = 500
    public static let stepCapacity = 60
    public private(set) var entries: [LauncherLogEntry] = []
    private var version = 1
    public var unreadCount: Int { entries.filter { $0.isNotification && !$0.isRead }.count }
    public var notifications: [LauncherLogEntry] {
        entries.filter(\.isNotification).sorted { $0.updatedAt > $1.updatedAt }
    }
    public init() {}

    @discardableResult
    public mutating func record(_ title: LocalizedMessage, level: LauncherLogEntry.Level = .info,
                                kind: LauncherLogEntry.Kind = .launcher, notify: Bool = true,
                                sessionID: UUID? = nil, fileURL: URL? = nil, date: Date = Date()) -> UUID {
        let title = sanitized(title)
        // Polling can report the same unavailable resource repeatedly. Preserve
        // the original unread state instead of making a new notification.
        if let existing = entries.first(where: {
            $0.status == .recorded && $0.titleMessage == title && $0.level == level && $0.kind == kind &&
            $0.sessionID == sessionID && $0.fileURL == fileURL && $0.isNotification == notify &&
            (0..<60).contains(date.timeIntervalSince($0.updatedAt))
        }) { return existing.id }
        let entry = LauncherLogEntry(id: UUID(), startedAt: date, updatedAt: date, kind: kind,
                                     titleMessage: title, level: level, status: .recorded,
                                     isNotification: notify, isRead: !notify, sessionID: sessionID, fileURL: fileURL)
        entries.insert(entry, at: 0); trim()
        return entry.id
    }

    public mutating func begin(_ title: LocalizedMessage, date: Date = Date()) -> UUID {
        let entry = LauncherLogEntry(id: UUID(), startedAt: date, updatedAt: date, kind: .task,
                                     titleMessage: sanitized(title), level: .info, status: .running,
                                     isNotification: false, isRead: true)
        entries.insert(entry, at: 0); trim()
        return entry.id
    }

    public mutating func progress(_ id: UUID, _ progress: InstallProgress, date: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.status == .running }) else { return }
        entries[index].completed = max(0, progress.completed)
        entries[index].total = max(0, progress.total)
        entries[index].updatedAt = date
        let message = sanitized(progress.message)
        if entries[index].steps.last?.message != message {
            entries[index].steps.append(.init(id: UUID(), date: date, message: message))
            if entries[index].steps.count > Self.stepCapacity { entries[index].steps.removeFirst() }
        }
    }

    public mutating func linkSession(_ sessionID: UUID, to id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].sessionID = sessionID
    }

    public mutating func annotate(_ id: UUID, message: LocalizedMessage, level: LauncherLogEntry.Level,
                                  sessionID: UUID? = nil, fileURL: URL? = nil) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let message = sanitized(message)
        entries[index].detailMessage = message
        if entries[index].steps.last?.message != message {
            entries[index].steps.append(.init(id: UUID(), date: Date(), message: message))
            if entries[index].steps.count > Self.stepCapacity { entries[index].steps.removeFirst() }
        }
        if level == .warning || level == .error || !entries[index].needsAttention { entries[index].level = level }
        if let sessionID { entries[index].sessionID = sessionID }
        if let fileURL { entries[index].fileURL = fileURL }
    }

    public mutating func finish(_ id: UUID, status: LauncherLogEntry.Status, detail: String? = nil, date: Date = Date()) {
        guard [.completed, .failed, .cancelled].contains(status),
              let index = entries.firstIndex(where: { $0.id == id && $0.status == .running }) else { return }
        entries[index].status = status
        entries[index].updatedAt = date
        if let detail { entries[index].detailMessage = sanitized(.verbatim(detail)) }
        if status == .failed { entries[index].level = .error }
        else if status == .cancelled { entries[index].level = entries[index].needsAttention ? .warning : .info }
        else if !entries[index].needsAttention { entries[index].level = .success }
        entries[index].isNotification = status != .cancelled || entries[index].needsAttention
        entries[index].isRead = !entries[index].isNotification
        trim()
    }

    public mutating func markRead(_ id: UUID? = nil) {
        for index in entries.indices where id == nil || entries[index].id == id { entries[index].isRead = true }
    }

    /// Clearing history never removes a running task or its cancellation target.
    public mutating func clearFinished() { entries.removeAll { $0.status != .running } }

    public mutating func recoverInterrupted(date: Date = Date()) {
        for index in entries.indices where entries[index].status == .running {
            entries[index].status = .interrupted
            entries[index].level = .warning
            entries[index].detailMessage = Messages.LauncherLog.interruptedDetail
            entries[index].updatedAt = date
            entries[index].isNotification = true
            entries[index].isRead = false
        }
        trim()
    }

    private mutating func trim() {
        let retained = Set(entries.filter { $0.status != .running }.sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.capacity).map(\.id))
        entries.removeAll { $0.status != .running && !retained.contains($0.id) }
    }

    private func sanitized(_ message: LocalizedMessage) -> LocalizedMessage {
        message.redacted { GameShareRedactor(homeDirectory: "").redact(String($0.prefix(8192))) }.recorded(limit: 8192)
    }

    public static func load(from url: URL) throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard result.version == 1 else { throw RuriError.message(Messages.LauncherLog.unsupportedHistory) }
        return result
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
