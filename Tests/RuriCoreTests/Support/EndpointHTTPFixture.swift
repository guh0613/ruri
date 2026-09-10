import Foundation

/// In-memory transport keyed by an isolated session header. Unregistered URLs
/// fail immediately instead of escaping to the network.
final class EndpointHTTPFixture: @unchecked Sendable {
    struct Response: Sendable {
        var data: Data = Data()
        var status = 200
        var headers = ["Content-Type": "application/json"]
    }
    struct Request: Sendable {
        let url: URL
        let method: String
        let headers: [String: String]
        let body: Data
        func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
    }
    private let id = UUID().uuidString
    private let lock = NSLock()
    private let handler: @Sendable (Request) -> Response?
    private var received: [Request] = []
    let session: URLSession
    var requests: [Request] { lock.withLock { received } }
    convenience init(_ responses: [String: Data]) {
        self.init { request in responses[(request.url.host ?? "") + request.url.path].map { Response(data: $0) } }
    }
    init(handler: @escaping @Sendable (Request) -> Response?) {
        self.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EndpointHTTPFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["Ruri-Stub-ID": id]
        session = URLSession(configuration: configuration)
        EndpointHTTPFixtureProtocol.registry.set(self, for: id)
    }
    func close() { session.invalidateAndCancel(); EndpointHTTPFixtureProtocol.registry.set(nil, for: id) }
    fileprivate func respond(_ request: URLRequest) -> Response? {
        guard let url = request.url else { return nil }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while body.count < 1_048_576 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }; body.append(contentsOf: buffer.prefix(count))
            }
        }
        let value = Request(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:], body: body)
        lock.withLock { received.append(value) }
        return handler(value)
    }
}

private final class EndpointHTTPFixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: EndpointHTTPFixture] = [:]
    func set(_ value: EndpointHTTPFixture?, for id: String) { lock.withLock { values[id] = value } }
    func get(_ id: String) -> EndpointHTTPFixture? { lock.withLock { values[id] } }
}
private final class EndpointHTTPFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let registry = EndpointHTTPFixtureRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let result = Self.registry.get(request.value(forHTTPHeaderField: "Ruri-Stub-ID") ?? "")?.respond(request),
              let url = request.url, let response = HTTPURLResponse(url: url, statusCode: result.status, httpVersion: "HTTP/1.1", headerFields: result.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: result.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
