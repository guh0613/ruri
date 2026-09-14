import Foundation
import Darwin
import RuriLocalization

/// A byte budget, not a line budget: even an unterminated line cannot grow it.
struct GameOutputTail {
    private var bytes: [UInt8]
    private var next = 0
    private(set) var count = 0
    private(set) var truncated = false

    init(capacity: Int = 262_144) { precondition(capacity > 0); bytes = .init(repeating: 0, count: capacity) }

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

/// The reader feeds this synchronously, so there is no second output queue.
/// Only the small tail is shared with control requests. Debug IO never holds
/// the tail lock and cannot delay a stop request by occupying the main actor.
final class GameOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var tail = GameOutputTail()
    private let redactor: GameLogRedactor
    private let truncatedNotice: String
    private let omittedNotice: String
    private var decoder: GameOutputDecoder
    private var debugLog: FileHandle?
    private var failure: String?
    private var debugBytes = 0
    private let debugByteLimit: Int
    private let limitNotice: String
    private var finished = false

    init(redactor: GameLogRedactor, debugLogURL: URL? = nil, debugByteLimit: Int = 64 * 1_048_576) throws {
        self.redactor = redactor
        self.debugByteLimit = max(0, debugByteLimit)
        limitNotice = Messages.MonitorLogging.debugLimit.localized
        truncatedNotice = Messages.CoreGameSession.truncatedLogNotice.localized
        omittedNotice = Messages.CoreLaunch.longLogLineOmitted.localized
        decoder = GameOutputDecoder(omitted: omittedNotice)
        if let debugLogURL {
            let fd = open(debugLogURL.path, O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            var attributes = stat()
            guard fstat(fd, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else { Darwin.close(fd); throw POSIXError(.EINVAL) }
            debugBytes = Int(attributes.st_size)
            debugLog = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        }
    }

    func receive(_ data: Data) {
        lock.lock(); tail.append(data); lock.unlock()
        if debugLog != nil { writeDebug(decoder.consume(data)) }
    }

    /// Called by ProcessOutputReader after its final drain, before onExit.
    func finish() {
        if debugLog != nil { writeDebug(decoder.consume(Data(), final: true)) }
        do { try debugLog?.close() } catch { failure = redactor.redact(error.localizedDescription) }
        debugLog = nil
        lock.lock(); finished = true; lock.unlock()
    }

    func snapshot(final: Bool = false) -> String {
        lock.lock()
        let data = tail.snapshot(final: final && finished), truncated = tail.truncated
        lock.unlock()
        return autoreleasepool {
            var decoder = GameOutputDecoder(omitted: omittedNotice)
            return (truncated ? truncatedNotice : "") + redactor.redact(decoder.consume(data, final: true))
        }
    }

    /// Read only after finish; failures are reported once, never once per line.
    var writeFailure: String? { failure }

    private func writeDebug(_ text: String) {
        guard !text.isEmpty, let debugLog else { return }
        do {
            let data = Data(redactor.redact(text).utf8)
            guard data.count <= debugByteLimit - min(debugBytes, debugByteLimit) else {
                failure = limitNotice
                try debugLog.close(); self.debugLog = nil
                return
            }
            try debugLog.write(contentsOf: data); debugBytes += data.count
        }
        catch {
            failure = redactor.redact(error.localizedDescription)
            try? debugLog.close(); self.debugLog = nil
        }
    }
}
