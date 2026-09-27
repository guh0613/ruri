import Foundation
import Network
import Testing
@testable import RuriCore

struct ServerStatusTests {
    @Test func parsingIsBoundedAndToleratesMissingOptionalFields() throws {
        let response = try ServerStatus.decode(Data(#"{"description":{"text":"§aHello","extra":[{"text":" world"}]},"players":{"online":4,"max":20,"sample":[{"name":"Player"}]},"version":{"name":"Proxy","protocol":47},"favicon":"not an image"}"#.utf8))
        #expect(response.description == "Hello world")
        #expect(response.online == 4 && response.maximum == 20 && response.protocolVersion == 47)
        #expect(response.icon == nil && response.playerSample == ["Player"])
        #expect(try ServerStatus.decode(Data("{}".utf8)).version == nil)
        #expect(throws: (any Error).self) { try ServerStatus.decode(Data(repeating: 32, count: 1_048_577)) }
        #expect(try ServerStatus.decode(Data(#"{"players":{"online":true,"max":-1}}"#.utf8)).online == nil)
    }
    @Test func framingHandlesFragmentsAndRejectsMaliciousLengths() throws {
        let frame = ServerPacket.frame(Data([0, 2, 123, 125]))
        var buffer = Data(frame.prefix(2))
        #expect(try ServerPacket.take(&buffer) == nil)
        buffer += frame.dropFirst(2)
        #expect(try ServerPacket.take(&buffer) == Data([0,2,123,125]) && buffer.isEmpty)
        for invalid in [Data([255,255,255,255,127]), ServerPacket.varInt(1_048_577), Data([0])] {
            var buffer = invalid
            #expect(throws: (any Error).self) { try ServerPacket.take(&buffer) }
        }
    }
    @Test func srvParsingAndPrioritySelection() throws {
        let host = Data([3]) + Data("srv".utf8) + Data([4]) + Data("test".utf8) + Data([0])
        let first = try MinecraftSRVRecord(Data([0,1,0,0,99,221]) + host)
        let second = try MinecraftSRVRecord(Data([0,2,0,100,99,222]) + host)
        #expect(first.port == 25565 && first.host == "srv.test")
        #expect(MinecraftSRVRecord.select([second, first]) == first)
        #expect(throws: (any Error).self) { try MinecraftSRVRecord(Data([0,0,0,0,99,221,192,0])) }
        #expect(try MinecraftSRVRecord(Data([0,0,0,0,0,0,0])).host.isEmpty)
    }
    @Test func realTCPStatusAndPong() async throws {
        let server = try StatusFixture(pong: true)
        let port = try await server.start(); defer { server.stop() }
        let response = try await ServerStatusClient.query(ServerAddress("127.0.0.1:\(port)"))
        #expect(response.description == "Fixture" && response.online == 3 && response.latencyMilliseconds != nil)
    }
    @Test func statusWithoutPongStillSucceeds() async throws {
        let server = try StatusFixture(pong: false)
        let port = try await server.start(); defer { server.stop() }
        let response = try await ServerStatusClient.query(ServerAddress("127.0.0.1:\(port)"), timeout: 0.3)
        #expect(response.description == "Fixture" && response.latencyMilliseconds == nil)
    }
    @Test func timeoutAndCancellationClosePendingConnections() async throws {
        let server = try StatusFixture(pong: false, respond: false)
        let port = try await server.start(); defer { server.stop() }
        let address = try ServerAddress("127.0.0.1:\(port)")
        await #expect(throws: ServerStatusError.timeout) { try await ServerStatusClient.query(address, timeout: 0.1) }
        let pending = Task { try await ServerStatusClient.query(address) }
        pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
    }
    @Test func launchDestinationsChooseVersionAppropriateArguments() throws {
        let address = try ServerAddress("[::1]:25566"), directory = URL(fileURLWithPath: "/game")
        for version in ["1.7.10", "1.8.9", "1.12.2", "1.16.5", "1.19.4"] {
            #expect(GameQuickPlay.supportsLegacyServer(version))
        }
        let old = GameQuickPlay.applying(.server(address), arguments: ["--server=old", "--port", "25565", "--quickPlaySingleplayer", "Old"], logging: nil, gameDirectory: directory)
        #expect(old == ["--server", "::1", "--port", "25566", "--gameDir", "/game"])
        let modern = GameQuickPlay.applying(.server(address), arguments: old, logging: URL(fileURLWithPath: "/log.json"), gameDirectory: directory)
        #expect(modern.contains("--quickPlayMultiplayer") && modern.contains("[::1]:25566") && !modern.contains("--server"))
        #expect(throws: (any Error).self) { try LaunchDestination.resolve(worldFolder: "World", serverAddress: "localhost") }
    }
}

private final class StatusFixture: @unchecked Sendable {
    let queue = DispatchQueue(label: "status-fixture")
    let listener: NWListener
    let pong: Bool
    let respond: Bool
    var connections: [NWConnection] = []
    init(pong: Bool, respond: Bool = true) throws { self.pong = pong; self.respond = respond; listener = try NWListener(using: .tcp, on: .any) }
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [self] state in
                if case .ready = state { listener.stateUpdateHandler = nil; continuation.resume(returning: listener.port!.rawValue) }
                if case .failed(let error) = state { listener.stateUpdateHandler = nil; continuation.resume(throwing: error) }
            }
            listener.newConnectionHandler = { [self] connection in connections.append(connection); connection.start(queue: queue); receive(connection, buffer: Data(), handshake: false) }
            listener.start(queue: queue)
        }
    }
    func receive(_ connection: NWConnection, buffer: Data, handshake: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, ended, error in
            guard !ended, error == nil else { return }
            var buffer = buffer + (data ?? Data()), handshake = handshake
            do {
                while let packet = try ServerPacket.take(&buffer) {
                    if !handshake { handshake = true; continue }
                    if packet == Data([0]), respond {
                        let json = #"{"description":"Fixture","players":{"online":3,"max":10}}"#
                        let response = ServerPacket.frame(Data([0]) + ServerPacket.string(json))
                        connection.send(content: Data(response.prefix(2)), completion: .contentProcessed { _ in
                            connection.send(content: Data(response.dropFirst(2)), completion: .contentProcessed { _ in })
                        })
                    } else if packet.first == 1, pong { connection.send(content: ServerPacket.frame(packet), completion: .contentProcessed { _ in }) }
                }
                receive(connection, buffer: buffer, handshake: handshake)
            } catch { connection.cancel() }
        }
    }
    func stop() { queue.sync { listener.newConnectionHandler = nil; listener.cancel(); for connection in connections { connection.cancel() }; connections = [] } }
}
