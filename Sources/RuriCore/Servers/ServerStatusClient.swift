import Foundation
import Network
import dnssd

public enum ServerStatusClient {
    public static func query(_ address: ServerAddress, protocolVersion: Int32 = -1, timeout: TimeInterval = 5) async throws -> ServerStatus {
        let probe = ServerStatusProbe(address: address, protocolVersion: protocolVersion, timeout: max(0.05, min(timeout, 30)))
        return try await probe.run()
    }
}

struct MinecraftSRVRecord: Equatable, Sendable {
    let priority: UInt16
    let weight: UInt16
    let port: UInt16
    let host: String
    init(_ data: Data) throws {
        guard data.count >= 7 else { throw ServerStatusError.dns }
        func number(_ index: Int) -> UInt16 { UInt16(data[index]) << 8 | UInt16(data[index + 1]) }
        priority = number(0); weight = number(2); port = number(4)
        var offset = 6, labels: [String] = []
        while offset < data.count {
            let count = Int(data[offset]); offset += 1
            if count == 0 { break }
            guard count <= 63, offset + count < data.count, let label = String(data: data[offset..<(offset + count)], encoding: .utf8) else { throw ServerStatusError.dns }
            labels.append(label); offset += count
        }
        guard offset == data.count, data.last == 0, port > 0 || labels.isEmpty else { throw ServerStatusError.dns }
        host = labels.joined(separator: ".")
        if !host.isEmpty { _ = try ServerAddress(host + ":" + String(port)) }
    }
    static func select(_ records: [Self]) -> Self? {
        guard let priority = records.map(\.priority).min() else { return nil }
        let candidates = records.filter { $0.priority == priority }.sorted { $0.weight < $1.weight }
        let total = candidates.reduce(0) { $0 + Int($1.weight) }
        if total == 0 { return candidates.randomElement() }
        var ticket = Int.random(in: 0...total)
        for record in candidates { ticket -= Int(record.weight); if ticket <= 0 { return record } }
        return candidates.last
    }
}

/// All mutable state lives on queue; cancellation closes DNS and TCP immediately.
private final class ServerStatusProbe: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.ruri.server-status", qos: .utility)
    let address: ServerAddress
    let protocolVersion: Int32
    let timeout: TimeInterval
    var continuation: CheckedContinuation<ServerStatus, any Error>?
    var cancelled = false
    var finished = false
    var connection: NWConnection?
    var dns: DNSServiceRef?
    var records: [MinecraftSRVRecord] = []
    var timer: DispatchWorkItem?
    var dnsTimer: DispatchWorkItem?
    var pongTimer: DispatchWorkItem?
    var buffer = Data()
    var status: ServerStatus?
    var pingStart: ContinuousClock.Instant?
    var nonce = Data()

    init(address: ServerAddress, protocolVersion: Int32, timeout: TimeInterval) { self.address = address; self.protocolVersion = protocolVersion; self.timeout = timeout }
    func run() async throws -> ServerStatus {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    self.continuation = continuation
                    if self.cancelled { self.complete(.failure(CancellationError())); return }
                    let timer = DispatchWorkItem { [weak self] in
                        guard let self else { return }
                        self.complete(self.status.map(Result.success) ?? .failure(ServerStatusError.timeout))
                    }
                    self.timer = timer; self.queue.asyncAfter(deadline: .now() + self.timeout, execute: timer)
                    self.resolve()
                }
            }
        } onCancel: {
            self.queue.async { self.cancelled = true; if self.continuation != nil { self.complete(.failure(CancellationError())) } }
        }
    }
    func resolve() {
        guard address.port == 25565, !address.isIP else { connect(host: address.host, port: address.port); return }
        let callback: DNSServiceQueryRecordReply = { _, flags, _, error, _, _, _, length, data, _, context in
            guard let context else { return }
            let owner = Unmanaged<ServerStatusProbe>.fromOpaque(context).takeUnretainedValue()
            guard !owner.finished, owner.connection == nil else { return }
            if error == kDNSServiceErr_NoError, let data,
               let record = try? MinecraftSRVRecord(Data(bytes: data, count: Int(length))), owner.records.count < 128 { owner.records.append(record) }
            if error != kDNSServiceErr_NoError || flags & UInt32(kDNSServiceFlagsMoreComing) == 0 { owner.resolved() }
        }
        let error = DNSServiceQueryRecord(&dns, UInt32(kDNSServiceFlagsReturnIntermediates), 0, "_minecraft._tcp." + address.host,
                                          UInt16(kDNSServiceType_SRV), UInt16(kDNSServiceClass_IN), callback, Unmanaged.passUnretained(self).toOpaque())
        guard error == kDNSServiceErr_NoError, let dns, DNSServiceSetDispatchQueue(dns, queue) == kDNSServiceErr_NoError else { resolved(); return }
        let timer = DispatchWorkItem { [weak self] in self?.resolved() }
        dnsTimer = timer; queue.asyncAfter(deadline: .now() + min(1.5, timeout / 2), execute: timer)
    }
    func resolved() {
        guard !finished, connection == nil else { return }
        dnsTimer?.cancel(); dnsTimer = nil
        if let dns { DNSServiceRefDeallocate(dns); self.dns = nil }
        if let record = MinecraftSRVRecord.select(records) {
            guard !record.host.isEmpty else { complete(.failure(ServerStatusError.dns)); return }
            connect(host: record.host, port: record.port)
        } else { connect(host: address.host, port: address.port) }
    }
    func connect(host: String, port: UInt16) {
        guard !finished, let port = NWEndpoint.Port(rawValue: port) else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.finished else { return }
            switch state {
            case .ready:
                self.send(ServerPacket.handshake(self.address, protocolVersion: self.protocolVersion)); self.receive()
            case .failed(let error), .waiting(let error):
                self.complete(self.status.map(Result.success) ?? .failure({ if case .dns = error { ServerStatusError.dns } else { ServerStatusError.connection } }()))
            default: break
            }
        }
        connection.start(queue: queue)
    }
    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, let error, !self.finished else { return }
            self.complete(self.status.map(Result.success) ?? .failure(error))
        })
    }
    func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, ended, error in
            guard let self, !self.finished else { return }
            do {
                if let data { self.buffer += data }
                guard self.buffer.count <= 1_114_112 else { throw ServerStatusError.response }
                while let packet = try ServerPacket.take(&self.buffer) { try self.packet(packet) }
                if self.finished { return }
                if ended || error != nil { self.complete(self.status.map(Result.success) ?? .failure(ServerStatusError.connection)) }
                else { self.receive() }
            } catch { self.complete(.failure(error)) }
        }
    }
    func packet(_ packet: Data) throws {
        var offset = 0
        guard let type = try ServerPacket.integer(packet, offset: &offset) else { throw ServerStatusError.response }
        if type == 0, status == nil {
            guard let length = try ServerPacket.integer(packet, offset: &offset), length == packet.count - offset else { throw ServerStatusError.response }
            status = try ServerStatus.decode(Data(packet.dropFirst(offset)))
            nonce = Data((0..<8).map { _ in UInt8.random(in: 0...255) }); pingStart = .now
            send(ServerPacket.frame(Data([1]) + nonce))
            let timer = DispatchWorkItem { [weak self] in if let self, let status = self.status { self.complete(.success(status)) } }
            pongTimer = timer; queue.asyncAfter(deadline: .now() + 1, execute: timer)
        } else if type == 1, Data(packet.dropFirst(offset)) == nonce, let start = pingStart, var status {
            status.latencyMilliseconds = Int(start.duration(to: .now).gameSeconds * 1000)
            complete(.success(status))
        } else { throw ServerStatusError.response }
    }
    func complete(_ result: Result<ServerStatus, any Error>) {
        guard !finished else { return }; finished = true
        timer?.cancel(); dnsTimer?.cancel(); pongTimer?.cancel()
        if let dns { DNSServiceRefDeallocate(dns); self.dns = nil }
        connection?.stateUpdateHandler = nil; connection?.cancel(); connection = nil
        continuation?.resume(with: result); continuation = nil
    }
}
