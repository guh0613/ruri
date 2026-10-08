import Foundation
import Darwin
import RuriLocalization

/// A connection is deliberately disposable: snapshots are bounded, subscriptions
/// coalesce, and a slow client is disconnected instead of delaying the game.
public final class GameMonitorObservation: @unchecked Sendable {
    public let updates: AsyncThrowingStream<MonitorUpdate, any Error>
    private let continuation: AsyncThrowingStream<MonitorUpdate, any Error>.Continuation
    private let queue = DispatchQueue(label: "dev.ruri.monitor-client", qos: .utility)
    private var peer: MonitorSocketPeer?
    private var cancelled = false
    private var latestOutput: GameOutputSnapshot?

    public init(session: GameSession, includeOutput: Bool = false) {
        let stream = AsyncThrowingStream<MonitorUpdate, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        updates = stream.stream; continuation = stream.continuation
        continuation.onTermination = { [weak self] _ in self?.cancel() }
        queue.async { [self] in
            guard !cancelled else { return }
            do {
                let request = try MonitorControlRequest.make(session, command: .subscribe, output: includeOutput)
                let fd = try MonitorSocket.connect(session)
                let peer = MonitorSocketPeer(descriptor: fd, queue: queue)
                peer.onFrame = { [weak self] data in
                    guard let self else { return }
                    do {
                        var update = try JSONDecoder().decode(MonitorUpdate.self, from: data)
                        guard update.sessionID == session.id, update.requestID == request.id else { throw POSIXError(.EPROTO) }
                        if let output = update.output {
                            if output.isReplacement { self.latestOutput = output }
                            else {
                                guard let previous = self.latestOutput, previous.revision <= output.revision,
                                      previous.text.utf8.count + output.text.utf8.count <= 2_097_152 else { throw POSIXError(.EPROTO) }
                                self.latestOutput = .init(revision: output.revision, text: previous.text + output.text, truncated: output.truncated, finished: output.finished)
                            }
                        }
                        // Reconstruct before bufferingNewest can coalesce UI
                        // delivery; dropping a delta must never corrupt a preview.
                        if includeOutput { update.output = self.latestOutput }
                        self.continuation.yield(update)
                    } catch { self.continuation.finish(throwing: error); self.cancel() }
                }
                peer.onClose = { [weak self] in self?.continuation.finish() }
                self.peer = peer; peer.start(); peer.send(try JSONEncoder().encode(request))
            } catch { continuation.finish(throwing: error) }
        }
    }
    public func cancel() {
        queue.async { [self] in cancelled = true; peer?.close(); peer = nil; continuation.finish() }
    }
    deinit { peer?.cancelFromAnyQueue() }
}
