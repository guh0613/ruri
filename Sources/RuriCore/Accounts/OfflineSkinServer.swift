import Foundation
import Network
import Security
import CryptoKit
import RuriLocalization

/// A per-game, loopback-only Yggdrasil texture service. It is owned by the
/// monitor, not the GUI, and never stores its ephemeral signing key on disk.
@MainActor final class OfflineSkinServer {
    private let listener: NWListener
    private let launch: OfflineSkinLaunch
    private let key: SecKey
    private let prefix = "/" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "/"
    private var startup: CheckedContinuation<Void, any Error>?
    private var timeout: Task<Void, Never>?
    private var connections: [UUID: SkinConnection] = [:]
    private(set) var root: URL?
    private(set) var metadata = Data()
    private var profile = Data()
    private let textures: [String: Data]
    private var stopped = false

    private init(_ launch: OfflineSkinLaunch) throws {
        try launch.validate()
        self.launch = launch
        var textures: [String: Data] = [:]
        for pixels in [launch.skin?.png, launch.capePNG].compactMap({ $0 }) {
            textures[Self.hash(pixels)] = pixels
        }
        self.textures = textures
        var failure: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, &failure) else {
            throw RuriError.message(Messages.OfflineSkin.signingFailed)
        }
        self.key = key
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    static func start(_ launch: OfflineSkinLaunch) async throws -> OfflineSkinServer {
        let server = try OfflineSkinServer(launch)
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { continuation in
                    server.startup = continuation
                    server.listener.stateUpdateHandler = { [weak server] state in
                        Task { @MainActor in server?.stateChanged(state) }
                    }
                    server.listener.newConnectionHandler = { [weak server] connection in
                        Task { @MainActor in
                            guard let server else { connection.cancel(); return }
                            server.accept(connection)
                        }
                    }
                    server.listener.start(queue: .main)
                    server.timeout = Task { @MainActor [weak server] in
                        do { try await Task.sleep(for: .seconds(8)) } catch { return }
                        server?.fail(RuriError.message(Messages.OfflineSkin.serviceFailed))
                    }
                }
                try Task.checkCancellation()
            } onCancel: {
                Task { @MainActor in server.stop() }
            }
            return server
        } catch { server.stop(); throw error }
    }

    func stop() {
        guard !stopped else { return }
        stopped = true; timeout?.cancel(); listener.cancel()
        let active = Array(connections.values)
        connections.removeAll()
        for connection in active { connection.close() }
        startup?.resume(throwing: CancellationError()); startup = nil
    }

    func applying(to original: LaunchPlan) throws -> LaunchPlan {
        guard let root, let index = launch.argumentIndex, original.arguments.indices.contains(index),
              original.offlineSkin?.account == launch.account else { throw RuriError.message(Messages.OfflineSkin.invalidConfiguration) }
        var plan = original
        plan.arguments.insert(contentsOf: ["-javaagent:\(launch.injector.path)=\(root.absoluteString)",
                                          "-Dauthlibinjector.side=client",
                                          "-Dauthlibinjector.yggdrasil.prefetched=" + metadata.base64EncodedString()], at: index)
        plan.offlineSkin = nil
        return plan
    }

    private func stateChanged(_ state: NWListener.State) {
        guard !stopped else { return }
        switch state {
        case .ready:
            guard startup != nil, let port = listener.port,
                  let root = URL(string: "http://127.0.0.1:\(port.rawValue)" + prefix) else { return }
            do {
                self.root = root
                try prepareResponses(root)
                timeout?.cancel(); startup?.resume(); startup = nil
            } catch { fail(error) }
        case .failed: fail(RuriError.message(Messages.OfflineSkin.serviceFailed))
        case .cancelled: stop()
        default: break
        }
    }
    private func fail(_ error: any Error) {
        startup?.resume(throwing: error); startup = nil
        stop()
    }
    private func prepareResponses(_ root: URL) throws {
        guard let publicKey = SecKeyCopyPublicKey(key), let raw = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            throw RuriError.message(Messages.OfflineSkin.signingFailed)
        }
        // Security exports RSA as PKCS#1; Java expects SubjectPublicKeyInfo.
        let rsaIdentifier = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        let spki = Self.der(0x30, rsaIdentifier + Self.der(0x03, Data([0]) + raw))
        let pem = "-----BEGIN PUBLIC KEY-----\n" + spki.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed]) + "\n-----END PUBLIC KEY-----"
        metadata = try JSONSerialization.data(withJSONObject: [
            "signaturePublickey": pem, "skinDomains": ["127.0.0.1"],
            "meta": ["serverName": "Ruri", "implementationName": "Ruri", "implementationVersion": "1", "feature.non_email_login": true]
        ])
        var textureInfo: [String: [String: Any]] = [:]
        if let skin = launch.skin {
            var texture: [String: Any] = ["url": root.appendingPathComponent("textures/" + Self.hash(skin.png)).absoluteString]
            if skin.model == .slim { texture["metadata"] = ["model": "slim"] }
            textureInfo["SKIN"] = texture
        }
        if let cape = launch.capePNG { textureInfo["CAPE"] = ["url": root.appendingPathComponent("textures/" + Self.hash(cape)).absoluteString] }
        let payload = try JSONSerialization.data(withJSONObject: ["timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "profileId": launch.account.uuid, "profileName": launch.account.username, "textures": textureInfo])
        let value = payload.base64EncodedString()
        guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA1, Data(value.utf8) as CFData, nil) as Data? else {
            throw RuriError.message(Messages.OfflineSkin.signingFailed)
        }
        profile = try JSONSerialization.data(withJSONObject: ["id": launch.account.uuid, "name": launch.account.username,
            "properties": [["name": "textures", "value": value, "signature": signature.base64EncodedString()]]])
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func der(_ tag: UInt8, _ body: Data) -> Data {
        var length = body.count
        var bytes: [UInt8] = []
        repeat { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 } while length > 0
        return Data([tag] + (body.count < 128 ? [UInt8(body.count)] : [0x80 | UInt8(bytes.count)] + bytes)) + body
    }

    private func accept(_ connection: NWConnection) {
        guard !stopped, connections.count < 16 else { connection.cancel(); return }
        let client = SkinConnection(connection: connection, server: self)
        connections[client.id] = client
        client.start()
    }
    fileprivate func forget(_ id: UUID) { connections[id] = nil }

    fileprivate func response(method: String, target: String, body: Data) -> SkinResponse {
        guard let components = URLComponents(string: target), components.scheme == nil, components.host == nil,
              components.path.hasPrefix(prefix) else { return .init(status: 404) }
        let path = String(components.path.dropFirst(prefix.count))
        if method == "GET" {
            if path.isEmpty { return .init(data: metadata) }
            if path.hasPrefix("textures/"), let pixels = textures[String(path.dropFirst("textures/".count))] {
                return .init(data: pixels, contentType: "image/png")
            }
            if path == "sessionserver/session/minecraft/profile/" + launch.account.uuid { return .init(data: profile) }
            if path == "sessionserver/session/minecraft/hasJoined" {
                let name = components.queryItems?.first { $0.name == "username" }?.value
                return name?.caseInsensitiveCompare(launch.account.username) == .orderedSame ? .init(data: profile) : .init(status: 204)
            }
            if path.hasPrefix("users/profiles/minecraft/") {
                let name = String(path.dropFirst("users/profiles/minecraft/".count))
                return name.caseInsensitiveCompare(launch.account.username) == .orderedSame ? simpleProfile() : .init(status: 204)
            }
        } else if method == "POST" {
            if path == "api/profiles/minecraft" || path == "minecraft/profile/lookup/bulk/byname" {
                guard let names = try? JSONDecoder().decode([String].self, from: body) else { return .init(status: 400) }
                let profiles = names.contains { $0.caseInsensitiveCompare(launch.account.username) == .orderedSame } ? [["id": launch.account.uuid, "name": launch.account.username]] : []
                return .init(data: (try? JSONEncoder().encode(profiles)) ?? Data("[]".utf8))
            }
            if path == "sessionserver/session/minecraft/join" { return .init(status: 204) }
        }
        return .init(status: 404)
    }
    private func simpleProfile() -> SkinResponse {
        .init(data: (try? JSONEncoder().encode(["id": launch.account.uuid, "name": launch.account.username])) ?? Data())
    }
}

fileprivate struct SkinResponse {
    var status = 200
    var data = Data()
    var contentType = "application/json; charset=utf-8"
    var encoded: Data {
        let reason = status == 200 ? "OK" : status == 204 ? "No Content" : status == 400 ? "Bad Request" : "Not Found"
        return Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(data.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n\r\n".utf8) + data
    }
}

/// Single-request HTTP connections with bounded headers/body and a fixed
/// lifetime. No filesystem routing, proxying, cookies, or external requests.
@MainActor private final class SkinConnection {
    let id = UUID()
    private let connection: NWConnection
    private weak var server: OfflineSkinServer?
    private var input = Data()
    private var timeout: Task<Void, Never>?
    private var closed = false
    init(connection: NWConnection, server: OfflineSkinServer) { self.connection = connection; self.server = server }
    func start() {
        connection.start(queue: .main)
        timeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.close()
        }
        receive()
    }
    func close() {
        guard !closed else { return }
        closed = true; timeout?.cancel(); connection.cancel(); server?.forget(id)
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, !self.closed else { return }
                if let data { self.input.append(data) }
                if self.input.count > 16_384 { self.send(.init(status: 400)); return }
                if self.process() { return }
                if complete || error != nil { self.close() } else { self.receive() }
            }
        }
    }
    private func process() -> Bool {
        guard let boundary = input.range(of: Data("\r\n\r\n".utf8)) else {
            if input.count > 8192 { send(.init(status: 400)); return true }
            return false
        }
        guard boundary.lowerBound <= 8192, let header = String(data: input[..<boundary.lowerBound], encoding: .utf8) else { send(.init(status: 400)); return true }
        let lines = header.components(separatedBy: "\r\n"), first = lines[0].split(separator: " ")
        guard first.count == 3, ["GET", "POST"].contains(first[0]), ["HTTP/1.0", "HTTP/1.1"].contains(first[2]) else { send(.init(status: 400)); return true }
        var length: Int?
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { send(.init(status: 400)); return true }
            let name = pair[0].lowercased()
            if name == "transfer-encoding" { send(.init(status: 400)); return true }
            if name == "content-length" {
                guard length == nil, let size = Int(pair[1].trimmingCharacters(in: .whitespaces)), (0...8192).contains(size) else { send(.init(status: 400)); return true }
                length = size
            }
        }
        let count = length ?? 0
        guard input.count >= boundary.upperBound + count else { return false }
        let body = input.subdata(in: boundary.upperBound..<(boundary.upperBound + count))
        send(server?.response(method: String(first[0]), target: String(first[1]), body: body) ?? .init(status: 404))
        return true
    }
    private func send(_ response: SkinResponse) {
        connection.send(content: response.encoded, completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in self?.close() }
        })
    }
}
