import Foundation
import Darwin

struct GameHostEvent: Decodable, Sendable {
    let version: Int
    let sessionID: UUID
    let pid: Int32
    let event: String
    let code: String?
    let value: Bool?
}

struct GameHostEventDecoder {
    private var buffer = Data()
    mutating func append(_ data: Data) throws -> [GameHostEvent] {
        buffer.append(data)
        var events: [GameHostEvent] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            guard (1...65536).contains(length) else { throw POSIXError(.EPROTO) }
            guard buffer.count >= length + 4 else { break }
            let event = try JSONDecoder().decode(GameHostEvent.self, from: buffer.subdata(in: 4..<(length + 4)))
            events.append(event)
            buffer.removeFirst(length + 4)
            // Rebase Data indices before parsing the next frame.
            buffer = Data(buffer)
        }
        return events
    }
}

/// A socket passed as stdin is used only for the bootstrap and host events.
/// The host duplicates it, then replaces Java's stdin with /dev/null.
final class GameHostConnection: @unchecked Sendable {
    let input: FileHandle
    private let peer: FileHandle
    private let queue = DispatchQueue(label: "dev.ruri.game-host", qos: .utility)
    private var reader: ProcessOutputReader?
    private var decoder = GameHostEventDecoder()
    private var closed = false
    private let request: GameHostRequest
    private let payload: Data
    private let receive: @Sendable (GameHostEvent) -> Void

    init(request: GameHostRequest, receive: @escaping @Sendable (GameHostEvent) -> Void) throws {
        let data = try JSONEncoder().encode(request)
        guard data.count <= 4 * 1_048_576 else { throw POSIXError(.E2BIG) }
        var length = UInt32(data.count).bigEndian
        var payload = withUnsafeBytes(of: &length) { Data($0) }; payload.append(data)
        var descriptors: [Int32] = [0, 0]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw POSIXError(.EMFILE) }
        for descriptor in descriptors {
            _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
            var flag: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &flag, socklen_t(MemoryLayout.size(ofValue: flag)))
        }
        peer = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true)
        input = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
        self.request = request; self.payload = payload; self.receive = receive
    }

    func started(pid: Int32) throws {
        try queue.sync {
            guard !closed else { throw POSIXError(.EBADF) }
            try input.close()
            reader = try ProcessOutputReader(handle: peer) { [weak self] data in
                guard let self else { return }
                self.queue.async { [self] in
                    guard !closed else { return }
                    do {
                        for event in try decoder.append(data) {
                            guard event.version == 1, event.sessionID == request.sessionID, event.pid == pid else { throw POSIXError(.EPROTO) }
                            receive(event)
                        }
                    } catch {
                        receive(.init(version: 1, sessionID: request.sessionID, pid: pid, event: "failed", code: "transport", value: nil))
                        closeOnQueue()
                    }
                }
            }
        }
        queue.async { [self] in
            guard !closed else { return }
            let deadline = ProcessInfo.processInfo.systemUptime + 15
            let succeeded = payload.withUnsafeBytes { bytes -> Bool in
                var offset = 0
                while offset < bytes.count && ProcessInfo.processInfo.systemUptime < deadline {
                    let count = Darwin.send(peer.fileDescriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, MSG_DONTWAIT)
                    if count > 0 { offset += count }
                    else if errno == EINTR { continue }
                    else if errno == EAGAIN || errno == EWOULDBLOCK {
                        var poller = pollfd(fd: peer.fileDescriptor, events: Int16(POLLOUT), revents: 0)
                        _ = poll(&poller, 1, 100)
                    } else { return false }
                }
                return offset == bytes.count
            }
            _ = shutdown(peer.fileDescriptor, SHUT_WR)
            if !succeeded {
                receive(.init(version: 1, sessionID: request.sessionID, pid: pid, event: "failed", code: "transport", value: nil))
                closeOnQueue()
            }
        }
    }
    func finish(_ completion: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            guard let reader else { closeOnQueue(); completion(); return }
            reader.finish { [self] in queue.async { [self] in closeOnQueue(); completion() } }
        }
    }
    func close() { queue.async { [self] in closeOnQueue() } }
    private func closeOnQueue() {
        guard !closed else { return }
        closed = true
        // The reader owns a duplicate descriptor. Shut down the socket itself
        // and finish that reader as well, so protocol errors cannot leak it.
        _ = shutdown(peer.fileDescriptor, SHUT_RDWR)
        reader?.finish {}
        try? input.close(); try? peer.close()
    }
}
