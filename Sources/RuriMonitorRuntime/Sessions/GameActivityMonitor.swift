import Foundation

@MainActor final class GameActivityMonitor {
    private let recorder: MonitorSessionRecorder
    private let logURL: URL?
    private let sample: () -> GameSessionTiming?
    private let feed: GameActivityLogFeed
    private var accumulator: GameActivityAccumulator
    private var lastVisit: QuickPlayVisit?
    private var pending: ServerAddress?
    private var barrier: Date?
    private var pendingSince: Date?
    private var fileTask: Task<Void, Never>?
    private var outputTask: Task<Void, Never>?
    private var observer: FileChangeObserver?
    private var stopped = false

    init(recorder: MonitorSessionRecorder, logURL: URL?, feed: GameActivityLogFeed, initial: GameSessionTiming, sample: @escaping () -> GameSessionTiming?) {
        self.recorder = recorder; self.logURL = logURL; self.feed = feed; self.sample = sample
        accumulator = .init(timing: initial)
    }
    func start() {
        if let timing = sample() { checkpoint(timing) }
        let version = recorder.record.gameVersion
        outputTask = Task { [weak self, feed] in
            var parser = GameActivityLogParser(version: version), expected: UInt64 = 1
            for await chunk in feed.stream {
                guard !Task.isCancelled, let self, !self.stopped else { break }
                if chunk.sequence != expected || chunk.data == nil { parser.reset(); self.event(.left(explicit: false)) }
                expected = chunk.sequence &+ 1
                if let data = chunk.data { for event in parser.consume(data) { self.event(event) } }
            }
        }
        if let logURL {
            let observer = FileChangeObserver(directories: [logURL.deletingLastPathComponent()], fallbackSeconds: 1)
            self.observer = observer
            fileTask = Task { [weak self] in
                self?.readQuickPlay()
                for await _ in observer.events {
                    guard !Task.isCancelled, let self, !self.stopped else { break }
                    self.readQuickPlay()
                }
            }
        }
    }
    func checkpoint(_ timing: GameSessionTiming) {
        accumulator.sample(timing)
        recorder.checkpoint(timing, activity: accumulator.tracking)
    }
    func finish(_ timing: GameSessionTiming, maximumSeconds: Double) async {
        feed.finish()
        await outputTask?.value
        fileTask?.cancel(); observer?.cancel()
        readQuickPlay()
        stopped = true
        accumulator.finish(timing, maximumSeconds: maximumSeconds)
        recorder.checkpoint(timing, activity: accumulator.tracking)
    }
    private func event(_ event: GameActivityLogEvent) {
        guard let timing = sample() else { return }
        switch event {
        case .connecting(let address):
            pending = address; pendingSince = timing.observedAt; barrier = timing.observedAt
            accumulator.change(to: .unattributed, source: .none, timing: timing)
        case .left(let explicit):
            pending = nil; pendingSince = nil; barrier = timing.observedAt
            accumulator.change(to: .unattributed, source: .none, timing: timing, explicitEnd: explicit)
        case .legacyJoined:
            guard logURL == nil, let pending, let since = pendingSince, timing.observedAt.timeIntervalSince(since) <= 120 else { return }
            accumulator.change(to: .server(address: pending, name: pending.authority), source: .log, timing: timing)
            self.pending = nil; pendingSince = nil
        }
        recorder.checkpoint(timing, activity: accumulator.tracking)
    }
    private func readQuickPlay() {
        guard let logURL, let timing = sample(), let data = try? SessionFileSystem.readBounded(logURL, limit: 65536),
              let visit = QuickPlayVisit.read(data, startedAt: timing.startedAt, now: timing.observedAt), visit != lastVisit,
              lastVisit.map({ visit.date >= $0.date }) ?? true,
              barrier.map({ visit.date >= $0 }) ?? true else { return }
        lastVisit = visit; pending = nil; pendingSince = nil
        accumulator.change(to: visit.target, source: .quickPlay, timing: timing)
        recorder.checkpoint(timing, activity: accumulator.tracking)
    }
    deinit { observer?.cancel(); fileTask?.cancel(); outputTask?.cancel(); feed.finish() }
}
