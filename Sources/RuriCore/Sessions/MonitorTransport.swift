import Foundation
import Darwin
import RuriLocalization

struct MonitorControlRequest: Codable, Sendable {
    enum Command: String, Codable, Sendable { case snapshot, subscribe, status, stop, quit }
    var version = 1
    let id: UUID
    let sessionID: UUID
    let monitor: ProcessIdentity
    let command: Command
    var output = false
}

public struct MonitorUpdate: Codable, Sendable {
    public let requestID: UUID
    public let sessionID: UUID
    public var session: GameSession?
    public var output: GameOutputSnapshot?
    public var accepted: Bool?
}

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

extension MonitorControlRequest {
    static func make(_ session: GameSession, command: Command, output: Bool = false) throws -> Self {
        guard let monitor = session.monitorIdentity, session.controlEndpoint != nil, monitor.isAlive else { throw RuriError.message(Messages.SessionRuntime.transportFailed) }
        return .init(id: UUID(), sessionID: session.id, monitor: monitor, command: command, output: output)
    }
}

enum MonitorSocket {
    static func address(_ path: String) throws -> sockaddr_un {
        let bytes = path.utf8CString
        var address = sockaddr_un()
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw POSIXError(.ENAMETOOLONG) }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(2 + bytes.count)
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            bytes.withUnsafeBytes { source in destination.copyBytes(from: source) }
        }
        return address
    }
    static func configure(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0, fcntl(fd, F_SETFD, FD_CLOEXEC) == 0 else { throw POSIXError(.EIO) }
        var value: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, socklen_t(MemoryLayout.size(ofValue: value))) == 0 else { throw POSIXError(.EIO) }
    }
    static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }
    static func connect(_ session: GameSession) throws -> Int32 {
        guard let endpoint = session.controlEndpoint, let identity = session.monitorIdentity, identity.isAlive else { throw POSIXError(.ENOTCONN) }
        // Endpoints live in a short, private mkdtemp directory (not inside an
        // arbitrarily long instance path). Refuse redirected/non-private roots.
        let parent = URL(fileURLWithPath: endpoint).deletingLastPathComponent().path
        var info = stat()
        guard parent.hasPrefix("/tmp/ruri-monitor-"), lstat(parent, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw POSIXError(.EACCES) }
        var address = try address(endpoint)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }
        do {
            try configure(fd)
            let addressLength = socklen_t(address.sun_len)
            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, addressLength) }
            }
            if result != 0 {
                guard errno == EINPROGRESS || errno == EAGAIN else { throw POSIXError(.ENOTCONN) }
                var event = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard poll(&event, 1, 1500) > 0 else { throw POSIXError(.ETIMEDOUT) }
                var error: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
                guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { throw POSIXError(.ENOTCONN) }
            }
            var pid: pid_t = 0, length = socklen_t(MemoryLayout<pid_t>.size)
            guard sameUser(fd), getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &length) == 0,
                  pid == identity.pid, identity.isAlive else { throw POSIXError(.EACCES) }
            return fd
        } catch { Darwin.close(fd); throw error }
    }

    /// Only called on an explicit action / utility task, never from the output
    /// drain. Bounded waits also support old synchronous CLI control APIs.
    static func request(_ session: GameSession, command: MonitorControlRequest.Command) throws -> MonitorUpdate {
        let request = try MonitorControlRequest.make(session, command: command)
        let fd = try connect(session); defer { Darwin.close(fd) }
        let data = try JSONEncoder().encode(request)
        var length = UInt32(data.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(data)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        try transfer(fd, data: &frame, writing: true, deadline: deadline)
        var header = Data(count: 4)
        try transfer(fd, data: &header, writing: false, deadline: deadline)
        let count = header.reduce(0) { ($0 << 8) | Int($1) }
        guard (1...2_097_152).contains(count) else { throw POSIXError(.EPROTO) }
        var payload = Data(count: count)
        try transfer(fd, data: &payload, writing: false, deadline: deadline)
        let reply = try JSONDecoder().decode(MonitorUpdate.self, from: payload)
        guard reply.sessionID == session.id, reply.requestID == request.id else { throw POSIXError(.EPROTO) }
        return reply
    }
    private static func transfer(_ fd: Int32, data: inout Data, writing: Bool, deadline: ContinuousClock.Instant) throws {
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard ContinuousClock.now < deadline else { throw POSIXError(.ETIMEDOUT) }
                let count = writing ? Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, MSG_DONTWAIT)
                                    : Darwin.recv(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, MSG_DONTWAIT)
                if count > 0 { offset += count }
                else if count == 0 { throw POSIXError(.ECONNRESET) }
                else if errno == EINTR { continue }
                else if errno == EAGAIN || errno == EWOULDBLOCK {
                    var event = pollfd(fd: fd, events: Int16(writing ? POLLOUT : POLLIN), revents: 0)
                    _ = poll(&event, 1, 100)
                } else { throw POSIXError(.EIO) }
            }
        }
    }
}

/// All mutable fields and callbacks are confined to queue. The server and client
/// own these peers, and cancel sources before descriptors can be recycled.
final class MonitorSocketPeer: @unchecked Sendable {
    let descriptor: Int32
    private let queue: DispatchQueue
    private let reader: DispatchSourceRead
    private let writer: DispatchSourceWrite
    private var writing = false
    private var closed = false
    private var input = Data()
    private var output = Data()
    private var offset = 0
    var onFrame: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var subscription: MonitorControlRequest?
    var handledRequest = false
    var lastOutput: GameOutputSnapshot?

    init(descriptor: Int32, queue: DispatchQueue) {
        self.descriptor = descriptor; self.queue = queue
        reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        writer = DispatchSource.makeWriteSource(fileDescriptor: descriptor, queue: queue)
        reader.setCancelHandler { Darwin.close(descriptor) }
        reader.setEventHandler { [weak self] in self?.read() }
        writer.setEventHandler { [weak self] in self?.flush() }
    }
    func start() { reader.resume() }
    func send(_ payload: Data) {
        guard !closed, payload.count <= 2_097_152, output.count - offset + payload.count + 4 <= 2_097_156 else { close(); return }
        if offset > 0 { output = Data(output.dropFirst(offset)); offset = 0 }
        var count = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &count) { output.append(contentsOf: $0) }
        output.append(payload)
        if !writing { writing = true; writer.resume() }
        flush()
    }
    private func flush() {
        guard !closed else { return }
        while offset < output.count {
            let count = output.withUnsafeBytes { Darwin.send(descriptor, $0.baseAddress!.advanced(by: offset), $0.count - offset, MSG_DONTWAIT) }
            if count > 0 { offset += count }
            else if count < 0 && errno == EINTR { continue }
            else if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { return }
            else { close(); return }
        }
        output.removeAll(keepingCapacity: true); offset = 0
        if writing { writing = false; writer.suspend() }
    }
    private func read() {
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var drained = 0
        while !closed && drained < 1_048_576 {
            let count = Darwin.recv(descriptor, &buffer, buffer.count, MSG_DONTWAIT)
            if count > 0 {
                drained += count; input.append(contentsOf: buffer.prefix(count))
                guard input.count <= 2_162_688 else { close(); return }
                while input.count >= 4 {
                    let length = input.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                    guard (1...2_097_152).contains(length) else { close(); return }
                    guard input.count >= length + 4 else { break }
                    let frame = input.subdata(in: 4..<(length + 4))
                    input = Data(input.dropFirst(length + 4))
                    onFrame?(frame)
                    if closed { return }
                }
            } else if count == 0 { close(); return }
            else if errno == EINTR { continue }
            else if errno == EAGAIN || errno == EWOULDBLOCK { return }
            else { close(); return }
        }
    }
    func close() {
        guard !closed else { return }
        closed = true
        reader.cancel()
        if !writing { writing = true; writer.resume() }
        writer.cancel()
        _ = shutdown(descriptor, SHUT_RDWR)
        let callback = onClose; onClose = nil; onFrame = nil; callback?()
    }
    func cancelFromAnyQueue() { queue.async { [self] in close() } }
}
