import Foundation
import Darwin
import RuriLocalization

/// A byte budget, not a line budget: even an unterminated line cannot grow it.
struct GameOutputTail {
    private var bytes: [UInt8]
    private var next = 0
    private(set) var count = 0
    private(set) var truncated = false

    init(capacity: Int = 262_144, truncated: Bool = false) { precondition(capacity > 0); bytes = .init(repeating: 0, count: capacity); self.truncated = truncated }

    mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let capacity = bytes.count
        truncated = truncated || data.count > capacity - count
        data.withUnsafeBytes { input in
            bytes.withUnsafeMutableBytes { output in
                if data.count >= capacity {
                    memcpy(output.baseAddress!, input.baseAddress!.advanced(by: data.count - capacity), capacity)
                    next = 0
                } else {
                    let first = min(data.count, capacity - next)
                    memcpy(output.baseAddress!.advanced(by: next), input.baseAddress!, first)
                    if first < data.count { memcpy(output.baseAddress!, input.baseAddress!.advanced(by: first), data.count - first) }
                    next = (next + data.count) % capacity
                }
            }
        }
        count = min(capacity, count + data.count)
    }

    func snapshot(final: Bool) -> Data {
        var result = Data()
        result.reserveCapacity(count)
        let start = count == bytes.count ? next : 0
        let first = min(count, bytes.count - start)
        result.append(contentsOf: bytes[start..<(start + first)])
        if first < count { result.append(contentsOf: bytes[..<(count - first)]) }
        // Never expose a credential fragment at a truncated line boundary.
        if truncated {
            guard let newline = result.firstIndex(of: 10) else { return Data() }
            result.removeSubrange(...newline)
        }
        if !final {
            guard let newline = result.lastIndex(of: 10) else { return Data() }
            result.removeSubrange(result.index(after: newline)...)
        }
        return result
    }
}

/// Formatting is used only by explicit debug capture or an on-demand snapshot.
/// Drop an oversized line as a whole rather than leaking partial credentials.
struct GameOutputDecoder {
    private var pending = Data()
    private var discardingLine = false
    private var formatter = GameLogFormatter()
    private let omitted: String
    init(omitted: String) { self.omitted = omitted }

    mutating func consume(_ data: Data, final: Bool = false) -> String {
        var result = "", start = data.startIndex
        func emit(_ line: String) { result += line + "\n" }
        while start < data.endIndex {
            let newline = data[start...].firstIndex(of: 10)
            let end = newline ?? data.endIndex
            if !discardingLine {
                if end - start > 262_144 - pending.count {
                    pending.removeAll(keepingCapacity: true); discardingLine = true
                    for line in formatter.flush() { emit(line) }
                    emit(omitted)
                } else { pending.append(data[start..<end]) }
            }
            if let newline {
                if !discardingLine {
                    for line in formatter.consume(String(decoding: pending, as: UTF8.self)) { emit(line) }
                }
                pending.removeAll(keepingCapacity: true); discardingLine = false
                start = newline + 1
            } else { break }
        }
        if final {
            if !discardingLine && !pending.isEmpty {
                for line in formatter.consume(String(decoding: pending, as: UTF8.self)) { emit(line) }
            }
            pending.removeAll(keepingCapacity: true)
            for line in formatter.flush() { emit(line) }
        }
        return result
    }
}

public struct GameOutputSnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let text: String
    public let truncated: Bool
    public let finished: Bool
    public var isReplacement = true
}

/// The hot path only copies bytes into fixed buffers. Formatting, disk IO and
/// subscribers never hold the capture lock and cannot back up the pipe reader.
final class GameOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = GameOutputTail()
    private var head = Data()
    private var received: UInt64 = 0
    private var finished = false
    private var observer: (@Sendable () -> Void)?
    private let redactor: GameLogRedactor
    private let truncatedNotice: String
    private let omittedNotice: String
    private let headNotice: String
    private let tailNotice: String
    private let debug: GameDebugWriter?

    init(redactor: GameLogRedactor, debugLogURL: URL? = nil, debugByteLimit: Int = 64 * 1_048_576) throws {
        self.redactor = redactor
        truncatedNotice = Messages.CoreGameSession.truncatedLogNotice.localized
        omittedNotice = Messages.CoreLaunch.longLogLineOmitted.localized
        headNotice = Messages.SessionRuntime.outputHead.localized
        tailNotice = Messages.SessionRuntime.outputTail.localized
        debug = try debugLogURL.map { try GameDebugWriter(url: $0, redactor: redactor, byteLimit: debugByteLimit) }
    }

    func receive(_ data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        tail.append(data)
        if head.count < 65_536 { head.append(data.prefix(65_536 - head.count)) }
        received &+= UInt64(data.count)
        let observer = observer
        lock.unlock()
        debug?.receive(data)
        observer?()
    }

    func observe(_ observer: (@Sendable () -> Void)?) {
        lock.lock(); self.observer = observer; lock.unlock()
    }
    /// Production uses the bounded asynchronous final drain. The synchronous
    /// variant is useful to deterministic byte-level tests without a live game.
    func finish() {
        markFinished()
        debug?.finishAndWait()
    }
    func finish(_ completion: @escaping @Sendable () -> Void) {
        markFinished()
        if let debug { debug.finish(completion) } else { completion() }
    }
    private func markFinished() {
        lock.lock(); finished = true; let observer = observer; lock.unlock()
        observer?()
    }
    var writeFailure: String? { debug?.failure }
    var isTruncated: Bool { lock.lock(); defer { lock.unlock() }; return tail.truncated }

    func snapshot(final: Bool = false, includeHead: Bool = false) -> String {
        snapshotValue(final: final, includeHead: includeHead).text
    }
    func snapshotValue(final: Bool = false, includeHead: Bool = false) -> GameOutputSnapshot {
        lock.lock()
        let data = tail.snapshot(final: final && finished), truncated = tail.truncated
        var first = head
        let revision = received, ended = finished
        lock.unlock()
        return autoreleasepool {
            var decoder = GameOutputDecoder(omitted: omittedNotice)
            var text = ""
            if includeHead && truncated {
                if let newline = first.lastIndex(of: 10) { first.removeSubrange(first.index(after: newline)...) } else { first.removeAll() }
                text = headNotice + "\n" + decoder.consume(first, final: true) + "\n" + tailNotice + "\n"
                decoder = GameOutputDecoder(omitted: omittedNotice)
            } else if truncated { text = truncatedNotice }
            text += decoder.consume(data, final: true)
            return .init(revision: revision, text: redactor.redact(text), truncated: truncated, finished: ended)
        }
    }
}

/// At most 1 MiB of undecoded output waits for the debug sink. A slow/full disk
/// disables detailed capture, rather than allocating an unbounded async queue.
private final class GameDebugWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.ruri.debug-output", qos: .utility, autoreleaseFrequency: .workItem)
    private let lock = NSLock()
    private var pendingBytes = 0
    private var accepting = true
    private var storedFailure: String?
    private var handle: FileHandle?
    private var decoder: GameOutputDecoder
    private let redactor: GameLogRedactor
    private let byteLimit: Int
    private var written: Int
    private let overloadNotice: String
    private let limitNotice: String

    init(url: URL, redactor: GameLogRedactor, byteLimit: Int) throws {
        self.redactor = redactor; self.byteLimit = max(0, byteLimit)
        decoder = GameOutputDecoder(omitted: Messages.CoreLaunch.longLogLineOmitted.localized)
        overloadNotice = Messages.SessionRuntime.debugOverload.localized
        limitNotice = Messages.MonitorLogging.debugLimit.localized
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        var attributes = stat()
        guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { Darwin.close(fd); throw POSIXError(.EINVAL) }
        written = Int(attributes.st_size)
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    var failure: String? { lock.lock(); defer { lock.unlock() }; return storedFailure }

    func receive(_ data: Data) {
        lock.lock()
        guard accepting else { lock.unlock(); return }
        if data.count > 1_048_576 - pendingBytes {
            accepting = false; storedFailure = overloadNotice; lock.unlock()
            queue.async { [self] in close() }
            return
        }
        pendingBytes += data.count
        lock.unlock()
        queue.async { [self] in
            if failure == nil { write(decoder.consume(data)) }
            lock.lock(); pendingBytes -= data.count; lock.unlock()
        }
    }
    func finishAndWait() {
        lock.lock(); accepting = false; lock.unlock()
        queue.sync { if failure == nil { write(decoder.consume(Data(), final: true)) }; close() }
    }
    func finish(_ completion: @escaping @Sendable () -> Void) {
        lock.lock(); accepting = false; lock.unlock()
        let once = OutputCompletion(completion)
        queue.async { [self] in
            if failure == nil { write(decoder.consume(Data(), final: true)) }
            close(); once.call()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
            once.call { lock.lock(); if storedFailure == nil { storedFailure = overloadNotice }; lock.unlock() }
        }
    }
    private func write(_ text: String) {
        guard !text.isEmpty, let handle else { return }
        do {
            let data = Data(redactor.redact(text).utf8)
            guard data.count <= byteLimit - min(written, byteLimit) else {
                lock.lock(); accepting = false; storedFailure = limitNotice; lock.unlock(); close(); return
            }
            try handle.write(contentsOf: data); written += data.count
        } catch {
            lock.lock(); accepting = false; storedFailure = redactor.redact(error.localizedDescription); lock.unlock(); close()
        }
    }
    private func close() { try? handle?.close(); handle = nil }
}

private final class OutputCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable () -> Void)?
    init(_ completion: @escaping @Sendable () -> Void) { self.completion = completion }
    func call(before: () -> Void = {}) {
        lock.lock(); let work = completion; completion = nil; lock.unlock()
        if let work { before(); work() }
    }
}
