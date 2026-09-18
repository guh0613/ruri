import Foundation
import CryptoKit
import Testing
@testable import RuriCore

private struct HTTPReply: Sendable {
    let status: Int
    let headers: [String: String]
    let data: Data
    var error: URLError.Code?
    var hold = false
}
private final class HTTPScenario: @unchecked Sendable {
    let lock = NSLock()
    var requests: [URLRequest] = []
    private var partialFile: URL?
    let reply: @Sendable (URLRequest, Int) -> HTTPReply
    init(_ reply: @escaping @Sendable (URLRequest, Int) -> HTTPReply) { self.reply = reply }
    func setPartialFile(_ url: URL) { lock.withLock { partialFile = url } }
    func hasPersistedPartial(_ data: Data) -> Bool {
        guard let file = lock.withLock({ partialFile }) else { return false }
        return (try? Data(contentsOf: file)) == data
    }
    func response(_ request: URLRequest) -> HTTPReply {
        let count = lock.withLock { requests.append(request); return requests.count }
        return reply(request, count)
    }
    var receivedRequests: [URLRequest] { lock.withLock { requests } }
}
private final class HTTPScenarios: @unchecked Sendable {
    let lock = NSLock()
    var entries: [String: HTTPScenario] = [:]
    func set(_ value: HTTPScenario?, host: String) { lock.withLock { entries[host] = value } }
    func get(_ host: String) -> HTTPScenario? { lock.withLock { entries[host] } }
}
private final class StubHTTP: URLProtocol, @unchecked Sendable {
    static let scenarios = HTTPScenarios()
    private let stopLock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host.flatMap { scenarios.get($0) } != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let scenario = Self.scenarios.get(request.url!.host!) else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        let reply = scenario.response(request)
        var headers = reply.headers; headers["Content-Type"] = "application/octet-stream"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        if !reply.data.isEmpty { client?.urlProtocol(self, didLoad: reply.data) }
        if let error = reply.error {
            Task {
                // URLSession may discard queued data on failure. Wait for the
                // partial write instead of assuming its delegate runs within 25 ms.
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while !scenario.hasPersistedPartial(reply.data) {
                    guard !self.stopLock.withLock({ self.stopped }) else { return }
                    guard ContinuousClock.now < deadline else {
                        Issue.record("Timed out waiting for the partial download before simulating a connection failure")
                        self.client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                guard !self.stopLock.withLock({ self.stopped }) else { return }
                self.client?.urlProtocol(self, didFailWithError: URLError(error))
            }
        } else if !reply.hold {
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { stopLock.withLock { stopped = true } }
}
private final class ProgressCapture: @unchecked Sendable {
    let lock = NSLock()
    var events: [DownloadTransferProgress] = []
    func append(_ value: DownloadTransferProgress) { lock.withLock { events.append(value) } }
    var values: [DownloadTransferProgress] { lock.withLock { events } }
}

struct DownloadTests {
    let body = Data((0..<512).map { UInt8($0 % 251) })
    private func setup(_ scenario: HTTPScenario) throws -> (DownloadManager, DownloadItem, URL, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let host = UUID().uuidString.lowercased() + ".ruri.test"
        StubHTTP.scenarios.set(scenario, host: host)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubHTTP.self]
        let item = DownloadItem(url: URL(string: "https://\(host)/artifact.jar")!, destination: root.appendingPathComponent("artifact.jar"), sha1: Insecure.SHA1.hash(data: body).map { String(format: "%02x", $0) }.joined(), size: Int64(body.count))
        scenario.setPartialFile(DownloadManager.partialFiles(item).data)
        return (DownloadManager(configuration: config, retryDelay: .zero), item, root, host)
    }
    @Test func retriesUsingVerifiedByteRange() async throws {
        let body = body
        let scenario = HTTPScenario { request, attempt in
            if attempt == 1 { return HTTPReply(status: 200, headers: ["Content-Length": "512", "ETag": "\"one\""], data: body.prefix(200), error: .networkConnectionLost) }
            return HTTPReply(status: 206, headers: ["Content-Range": "bytes 200-511/512", "Content-Length": "312", "ETag": "\"one\""], data: body.dropFirst(200))
        }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        let progress = ProgressCapture()
        try await manager.fetch(item) { progress.append($0) }
        #expect(try Data(contentsOf: item.destination) == body)
        let requests = scenario.receivedRequests
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "Range") == "bytes=200-")
        #expect(requests.last?.value(forHTTPHeaderField: "If-Range") == "\"one\"")
        #expect(progress.values.contains { $0.resumedBytes == 200 })
        let transfer = try #require(await manager.transfers().first)
        #expect(transfer.state == .completed); #expect(transfer.receivedBytes == 512)
        #expect(transfer.attempt == 2); #expect(transfer.resumedBytes == 200)
        #expect(!FileManager.default.fileExists(atPath: DownloadManager.partialFiles(item).data.path))
    }
    @Test(arguments: [0.0, 0.1])
    func serverIgnoringRangeRestartsCleanly(responseDelay: TimeInterval) async throws {
        let body = body
        let scenario = HTTPScenario { _, attempt in
            HTTPReply(status: 200, headers: ["Content-Length": "512", "ETag": "\"v\(attempt)\""], data: attempt == 1 ? body.prefix(123) : body, error: attempt == 1 ? .networkConnectionLost : nil)
        }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        try await manager.fetch(item) { progress in
            // Reproduce a busy runner delaying response acceptance past the old stub timer.
            if progress.receivedBytes == 0 { Thread.sleep(forTimeInterval: responseDelay) }
        }
        #expect(try Data(contentsOf: item.destination) == body)
        let requests = scenario.receivedRequests
        #expect(requests.count == 2)
        #expect(requests.first?.value(forHTTPHeaderField: "Range") == nil)
        #expect(requests.last?.value(forHTTPHeaderField: "Range") == "bytes=123-")
        #expect(requests.last?.value(forHTTPHeaderField: "If-Range") == "\"v1\"")
        #expect(!FileManager.default.fileExists(atPath: DownloadManager.partialFiles(item).data.path))
    }
    @Test func invalidRangeDiscardsPartialAndRetriesFromStart() async throws {
        let body = body
        let scenario = HTTPScenario { _, attempt in
            if attempt == 1 { return HTTPReply(status: 200, headers: ["Content-Length": "512"], data: body.prefix(100), error: .networkConnectionLost) }
            if attempt == 2 { return HTTPReply(status: 206, headers: ["Content-Range": "bytes 101-511/512"], data: body.dropFirst(101)) }
            return HTTPReply(status: 200, headers: ["Content-Length": "512"], data: body)
        }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        try await manager.fetch(item)
        #expect(try Data(contentsOf: item.destination) == body)
        #expect(scenario.receivedRequests.count == 3)
        #expect(scenario.receivedRequests.last?.value(forHTTPHeaderField: "Range") == nil)
    }
    @Test func cancellationKeepsPartialForNewManager() async throws {
        let body = body
        let scenario = HTTPScenario { _, attempt in
            if attempt == 1 { return HTTPReply(status: 200, headers: ["Content-Length": "512", "ETag": "\"one\""], data: body.prefix(200), hold: true) }
            return HTTPReply(status: 206, headers: ["Content-Range": "bytes 200-511/512"], data: body.dropFirst(200))
        }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        let progress = ProgressCapture()
        let operation = Task { try await manager.fetch(item) { progress.append($0) } }
        // File writes precede reports. Bound the wait so a broken callback fails.
        let partial = DownloadManager.partialFiles(item)
        for _ in 0..<100 {
            if (try? Data(contentsOf: partial.data).count) == 200 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(await manager.transfers().first?.state == .cancelled)
        #expect(try Data(contentsOf: partial.data).count == 200)
        #expect(!FileManager.default.fileExists(atPath: item.destination.path))
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubHTTP.self]
        try await DownloadManager(configuration: config, retryDelay: .zero).fetch(item)
        #expect(scenario.receivedRequests.last?.value(forHTTPHeaderField: "Range") == "bytes=200-")
        #expect(try Data(contentsOf: item.destination) == body)
    }
    @Test func corruptDownloadsNeverReplaceExistingFile() async throws {
        let scenario = HTTPScenario { _, _ in HTTPReply(status: 200, headers: ["Content-Length": "512"], data: Data(repeating: 0, count: 512)) }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        try Data("keep previous".utf8).write(to: item.destination)
        await #expect(throws: (any Error).self) { try await manager.fetch(item) }
        #expect(await manager.transfers().first?.state == .failed)
        #expect(try Data(contentsOf: item.destination) == Data("keep previous".utf8))
        #expect(!FileManager.default.fileExists(atPath: DownloadManager.partialFiles(item).data.path))
    }
    @Test func contentRangeRejectsOverflowAndInvalidBounds() throws {
        #expect(try HTTPContentRange("bytes 0-99/100").total == 100)
        for value in ["bytes -1-3/10", "bytes 2-1/10", "bytes 0-10/10", "bytes 0-2/*", "bytes 0-999999999999999999999/100", "items 0-2/3"] {
            #expect(throws: (any Error).self) { try HTTPContentRange(value) }
        }
    }
    @Test func resumeUsesOnlyValidStrongETags() {
        #expect(DownloadResumeState(identity: "x", etag: "\"version\"", lastModified: "date").validator == "\"version\"")
        #expect(DownloadResumeState(identity: "x", etag: "W/\"weak\"", lastModified: "date").validator == "date")
        #expect(DownloadResumeState(identity: "x", etag: "0x8DCB7A74F8D4DDF", lastModified: "date").validator == "date")
        #expect(DownloadResumeState(identity: "x", etag: "bare", lastModified: nil).validator == nil)
    }
    @Test func simultaneousRequestsShareOneTransfer() async throws {
        let body = body
        let scenario = HTTPScenario { _, _ in HTTPReply(status: 200, headers: ["Content-Length": "512"], data: body) }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        async let first: Void = manager.fetch(item)
        async let second: Void = manager.fetch(item)
        _ = try await (first, second)
        #expect(scenario.receivedRequests.count == 1)
        #expect(DownloadManager.valid(item.destination, item: item))
    }
    @Test func separateManagersCannotWriteOnePartialConcurrently() async throws {
        let body = body
        let scenario = HTTPScenario { _, _ in HTTPReply(status: 200, headers: ["Content-Length": "512"], data: body) }
        let (firstManager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubHTTP.self]
        let secondManager = DownloadManager(configuration: config, retryDelay: .zero)
        async let first: Void = firstManager.fetch(item)
        async let second: Void = secondManager.fetch(item)
        _ = try await (first, second)
        #expect(scenario.receivedRequests.count == 1)
        #expect(DownloadManager.valid(item.destination, item: item))
    }
    @Test func refusesRedirectedPartialDirectory() async throws {
        let scenario = HTTPScenario { _, _ in HTTPReply(status: 200, headers: [:], data: Data()) }
        let (manager, item, root, host) = try setup(scenario)
        defer { StubHTTP.scenarios.set(nil, host: host); try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("other-data")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".ruri-partials"), withDestinationURL: outside)
        await #expect(throws: (any Error).self) { try await manager.fetch(item) }
        #expect(scenario.receivedRequests.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    @Test func failedMirrorFallsBackForMetadataAndFiles() async throws {
        let body = body
        let mirror = HTTPScenario { _, _ in HTTPReply(status: 503, headers: [:], data: Data()) }
        let original = HTTPScenario { _, _ in HTTPReply(status: 200, headers: ["Content-Length": "512"], data: body) }
        StubHTTP.scenarios.set(mirror, host: "bmclapi2.bangbang93.com")
        StubHTTP.scenarios.set(original, host: "libraries.minecraft.net")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { StubHTTP.scenarios.set(nil, host: "bmclapi2.bangbang93.com"); StubHTTP.scenarios.set(nil, host: "libraries.minecraft.net"); try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubHTTP.self]
        let routing = NetworkRouting(source: .bmclapi)
        let url = URL(string: "https://libraries.minecraft.net/test/artifact.jar")!
        let client = HTTPClient(session: URLSession(configuration: config), routing: routing)
        #expect(try await client.data(from: url) == body)
        let item = DownloadItem(url: url, destination: root.appendingPathComponent("artifact.jar"), sha1: Insecure.SHA1.hash(data: body).map { String(format: "%02x", $0) }.joined(), size: 512)
        try await DownloadManager(configuration: config, retryDelay: .zero, routing: routing).fetch(item)
        #expect(DownloadManager.valid(item.destination, item: item))
        #expect(mirror.receivedRequests.count == 2); #expect(original.receivedRequests.count == 2)
        #expect(mirror.receivedRequests.allSatisfy { $0.url?.path == "/libraries/test/artifact.jar" })
    }
}
