import Foundation

public enum GameActivityTarget: Codable, Equatable, Sendable {
    case unattributed
    case world(folder: String, name: String)
    case server(address: ServerAddress, name: String)
    public var kind: String { switch self { case .unattributed: "unattributed"; case .world: "world"; case .server: "server" } }
    public var key: String { switch self { case .unattributed: ""; case .world(let folder, _): folder; case .server(let address, _): address.key } }
    public var name: String { switch self { case .unattributed: ""; case .world(_, let name), .server(_, let name): name } }
    var valid: Bool {
        guard name.utf8.count <= 1024 else { return false }
        if case .world(let folder, let name) = self { return GameWorldPlay(folder: folder, name: name, source: .detected).isValid }
        return true
    }
}

public struct GameActivitySegment: Codable, Identifiable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case none, quickPlay, log }
    public enum Quality: String, Codable, Sendable { case observed, estimated, interrupted }
    public let id: UUID
    public let target: GameActivityTarget
    public let source: Source
    public let startedAt: Date
    public var endedAt: Date
    public var seconds: Double
    public var days: [GameSessionTiming.Day]
    public var quality: Quality
}

/// Persisted attribution uses the same measured awake clock as instance time.
/// Wall timestamps describe events, never determine credited duration.
public struct GameActivityTracking: Codable, Equatable, Sendable {
    public var version = 1
    public var segments: [GameActivitySegment]
    public var observedAwakeSeconds: Double
    public var observedDays: [GameSessionTiming.Day]
    public var complete: Bool
    public var attributedSeconds: Double { segments.filter { $0.target != .unattributed }.reduce(0) { $0 + $1.seconds } }
    public var unattributedSeconds: Double { segments.filter { $0.target == .unattributed }.reduce(0) { $0 + $1.seconds } }
    func valid(total: Double) -> Bool {
        version == 1 && segments.count <= 513 && observedAwakeSeconds.isFinite && observedAwakeSeconds >= 0 && observedAwakeSeconds <= total + 0.1 &&
        observedDays.count <= 4096 && Set(segments.map(\.id)).count == segments.count &&
        segments.allSatisfy { segment in
            segment.target.valid && segment.seconds.isFinite && segment.seconds >= 0 && segment.days.count <= 4096 &&
            segment.startedAt.timeIntervalSince1970.isFinite && segment.endedAt.timeIntervalSince1970.isFinite && segment.endedAt >= segment.startedAt &&
            segment.days.allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 } && abs(segment.days.reduce(0) { $0 + $1.seconds } - segment.seconds) < 0.1
        } && abs(segments.reduce(0) { $0 + $1.seconds } - observedAwakeSeconds) < 0.1
    }
    mutating func interrupt() {
        complete = true
        if !segments.isEmpty { segments[segments.count - 1].quality = .interrupted }
    }
}

struct GameActivityAccumulator {
    private(set) var tracking: GameActivityTracking
    init(timing: GameSessionTiming) {
        tracking = .init(segments: [.init(id: UUID(), target: .unattributed, source: .none, startedAt: timing.startedAt, endedAt: timing.startedAt, seconds: 0, days: [], quality: .observed)], observedAwakeSeconds: 0, observedDays: [], complete: false)
        sample(timing)
    }
    mutating func sample(_ timing: GameSessionTiming) {
        guard !tracking.complete, let index = tracking.segments.indices.last else { return }
        let delta = max(0, timing.awakeSeconds - tracking.observedAwakeSeconds)
        let previous = Dictionary(tracking.observedDays.map { ($0.date, $0.seconds) }, uniquingKeysWith: max)
        var remaining = delta
        for day in timing.days {
            let seconds = min(remaining, max(0, day.seconds - (previous[day.date] ?? 0)))
            if seconds > 0 { creditDay(day.date, seconds: seconds, index: index); remaining -= seconds }
        }
        if remaining > 0 {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: timing.timeZoneIdentifier) ?? .current
            creditDay(calendar.startOfDay(for: timing.observedAt), seconds: remaining, index: index)
        }
        tracking.segments[index].seconds += delta
        tracking.segments[index].endedAt = max(tracking.segments[index].startedAt, timing.observedAt)
        tracking.observedAwakeSeconds = max(tracking.observedAwakeSeconds, timing.awakeSeconds)
        tracking.observedDays = timing.days
    }
    private mutating func creditDay(_ date: Date, seconds: Double, index: Int) {
        if let dayIndex = tracking.segments[index].days.firstIndex(where: { $0.date == date }) { tracking.segments[index].days[dayIndex].seconds += seconds }
        else { tracking.segments[index].days.append(.init(date: date, seconds: seconds)) }
    }
    mutating func change(to target: GameActivityTarget, source: GameActivitySegment.Source, timing: GameSessionTiming, explicitEnd: Bool = false) {
        sample(timing)
        guard !tracking.complete, target.valid else { return }
        if tracking.segments.last?.target == .unattributed && target == .unattributed { return }
        if explicitEnd, let last = tracking.segments.indices.last, tracking.segments[last].source == .quickPlay { tracking.segments[last].quality = .observed }
        // Bound even a hostile client that generates a new target every frame.
        if tracking.segments.count >= 512 {
            if tracking.segments.last?.target != .unattributed { tracking.segments.append(.init(id: UUID(), target: .unattributed, source: .none, startedAt: timing.observedAt, endedAt: timing.observedAt, seconds: 0, days: [], quality: .observed)) }
            return
        }
        tracking.segments.append(.init(id: UUID(), target: target, source: source, startedAt: timing.observedAt, endedAt: timing.observedAt, seconds: 0, days: [], quality: target == .unattributed ? .observed : .estimated))
    }
    mutating func finish(_ timing: GameSessionTiming, maximumSeconds: Double? = nil) {
        sample(timing)
        // Output drains can finish after the process exits. Never credit that
        // drain time, even if an earlier live sample arrived during the drain.
        let maximum = max(0, maximumSeconds ?? timing.awakeSeconds)
        var excess = max(0, tracking.observedAwakeSeconds - maximum)
        for index in tracking.segments.indices.reversed() where excess > 0 {
            let removed = min(excess, tracking.segments[index].seconds)
            tracking.segments[index].seconds -= removed; excess -= removed
            var dayExcess = removed
            for day in tracking.segments[index].days.indices.reversed() where dayExcess > 0 {
                let amount = min(dayExcess, tracking.segments[index].days[day].seconds)
                tracking.segments[index].days[day].seconds -= amount; dayExcess -= amount
            }
        }
        tracking.observedAwakeSeconds = min(tracking.observedAwakeSeconds, maximum)
        tracking.complete = true
    }
}

extension GameSession {
    public var activitySegments: [GameActivitySegment] { activity?.segments ?? [] }
    public func seconds(worldFolder: String) -> Double {
        if let activity { return activity.segments.filter { $0.target.kind == "world" && $0.target.key == worldFolder }.reduce(0) { $0 + $1.seconds } }
        return world?.folder == worldFolder ? playedSeconds : 0
    }
}
