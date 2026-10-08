import Foundation
import Darwin

/// Coalesces filesystem notifications into a single pending wakeup. The timer
/// covers unavailable/moved directories and filesystems that miss notifications.
public final class FileChangeObserver: @unchecked Sendable {
    public let events: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let sources: [any DispatchSourceProtocol]

    public init(directories: [URL], processes: [Int32] = [], fallbackSeconds: Int = 15) {
        let stream = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = stream.stream; continuation = stream.continuation
        let continuation = stream.continuation
        let queue = DispatchQueue(label: "dev.ruri.file-changes", qos: .utility)
        var sources: [any DispatchSourceProtocol] = []
        for path in Set(directories.map(\.path)) {
            let fd = open(path, O_EVTONLY | O_CLOEXEC)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            source.setEventHandler { continuation.yield(()) }
            source.setCancelHandler { Darwin.close(fd) }
            source.resume(); sources.append(source)
        }
        for pid in Set(processes) where pid > 0 {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            source.setEventHandler { continuation.yield(()) }
            source.resume(); sources.append(source)
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let seconds = max(1, fallbackSeconds)
        timer.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds), leeway: .seconds(1))
        timer.setEventHandler { continuation.yield(()) }
        timer.resume(); sources.append(timer)
        self.sources = sources
    }
    public func cancel() {
        for source in sources { source.cancel() }
        continuation.finish()
    }
    deinit { cancel() }
}
