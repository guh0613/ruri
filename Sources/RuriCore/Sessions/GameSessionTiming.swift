import Foundation

/// Persisted measurements, not a wall-clock subtraction. Checkpoints remain a
/// lower bound after an unobserved exit; recovery never invents the missing time.
public struct GameSessionTiming: Codable, Equatable, Sendable {
    public struct Day: Codable, Equatable, Sendable {
        public let date: Date
        public var seconds: Double
    }
    public enum Quality: String, Codable, Sendable { case checkpoint, complete, interrupted }
    public let version: Int
    public let startedAt: Date
    public var observedAt: Date
    public var awakeSeconds: Double
    public var elapsedSeconds: Double
    public var quality: Quality
    public let timeZoneIdentifier: String
    public var days: [Day]

    var isValid: Bool {
        version == 1 && awakeSeconds.isFinite && awakeSeconds >= 0 && elapsedSeconds.isFinite && elapsedSeconds >= 0 &&
        awakeSeconds <= elapsedSeconds + 1 && days.count <= 4096 && days.reduce(0, { $0 + $1.seconds }).isFinite && days.allSatisfy { $0.seconds.isFinite && $0.seconds >= 0 }
    }
}

/// Pure accumulation makes clock changes and day boundaries testable without
/// putting the test machine to sleep. A sleeping interval contributes no time.
struct GameTimingAccumulator {
    private(set) var timing: GameSessionTiming
    private let calendar: Calendar

    init(startedAt: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        self.calendar = calendar
        timing = .init(version: 1, startedAt: startedAt, observedAt: startedAt, awakeSeconds: 0, elapsedSeconds: 0,
                       quality: .checkpoint, timeZoneIdentifier: timeZone.identifier, days: [])
    }

    mutating func sample(at date: Date, awakeSeconds: Double, elapsedSeconds: Double, final: Bool = false) -> GameSessionTiming {
        let awake = max(timing.awakeSeconds, awakeSeconds.isFinite ? awakeSeconds : timing.awakeSeconds)
        let delta = awake - timing.awakeSeconds
        let wall = date.timeIntervalSince(timing.observedAt)
        if delta > 0 {
            // Sleep/wake callbacks split sleeping intervals. If a clock is moved
            // backwards, or an event is missed, attribute only the measured time.
            let start = wall > 0 && wall <= delta + 5 ? timing.observedAt : date.addingTimeInterval(-delta)
            var cursor = start
            let duration = max(0.001, date.timeIntervalSince(start))
            while cursor < date {
                let day = calendar.startOfDay(for: cursor)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > cursor else { break }
                let end = min(date, next)
                let seconds = delta * end.timeIntervalSince(cursor) / duration
                if let index = timing.days.lastIndex(where: { $0.date == day }) { timing.days[index].seconds += seconds }
                else if timing.days.count < 4096 { timing.days.append(.init(date: day, seconds: seconds)) }
                cursor = end
            }
        }
        timing.awakeSeconds = awake
        timing.elapsedSeconds = max(timing.elapsedSeconds, elapsedSeconds.isFinite ? elapsedSeconds : timing.elapsedSeconds)
        timing.observedAt = date
        timing.quality = final ? .complete : .checkpoint
        return timing
    }
}

extension Duration {
    var gameSeconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

extension GameSession {
    public var playedSeconds: Double { exit?.playTime ?? timing?.awakeSeconds ?? 0 }
    public var hasPlayed: Bool { exit != nil || timing != nil || gameIdentity != nil }
    public var hasPostCommandFailure: Bool { commandResults?.contains { $0.phase == .after && !$0.succeeded && !$0.cancelled } == true }
    public var needsAttention: Bool {
        state == .failed || state == .interrupted || commandResults?.contains(where: { !$0.succeeded && !$0.cancelled }) == true
    }
}
