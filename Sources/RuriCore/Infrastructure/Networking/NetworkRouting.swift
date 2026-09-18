import RuriLocalization
import Foundation

public enum DownloadSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, official, bmclapi
    public var id: String { rawValue }
    public var title: String { switch self { case .automatic: Messages.CoreNetworkRouting.automaticRouting.localized; case .official: Messages.CoreNetworkRouting.officialSource.localized; case .bmclapi: Messages.CoreNetworkRouting.bmclapiPreferred.localized } }
    public func candidates(for url: URL) -> [URL] {
        guard self != .official else { return [url] }
        if let mirror = Self.mirror(url) { return self == .bmclapi ? [mirror, url] : [url, mirror] }
        // Mod CDNs only fall back to MCIM after the official host fails.
        if let mirror = MCIMEndpoints.mirror(url) { return [url, mirror] }
        return [url]
    }
    static func mirror(_ url: URL) -> URL? { BMCLAPIEndpoints.mirror(url) }
}

public actor NetworkRouting {
    public static let shared = NetworkRouting()
    private var source: DownloadSource
    public init(source: DownloadSource = .automatic) { self.source = source }
    public func configure(_ source: DownloadSource) { self.source = source }
    public func candidates(for url: URL) -> [URL] { source.candidates(for: url) }
    public func candidates(for request: URLRequest) -> [URL] {
        guard let url = request.url else { return [] }
        guard ["GET", "HEAD"].contains(request.httpMethod ?? "GET"),
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "X-API-Key") == nil else { return [url] }
        return source.candidates(for: url)
    }
}
