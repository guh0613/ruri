import Foundation

public enum DownloadSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, official, bmclapi
    public var id: String { rawValue }
    public var title: String { switch self { case .automatic: "自动切换"; case .official: "官方源"; case .bmclapi: "BMCLAPI 优先" } }
    public func candidates(for url: URL) -> [URL] {
        guard self != .official, let mirror = Self.mirror(url) else { return [url] }
        return self == .bmclapi ? [mirror, url] : [url, mirror]
    }
    // Only public game metadata and artifacts have mirror equivalents. Account,
    // content-provider and arbitrary URLs always retain their original service.
    static func mirror(_ url: URL) -> URL? {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let path = parts.percentEncodedPath
        switch parts.host?.lowercased() {
        case "launchermeta.mojang.com", "launcher.mojang.com", "piston-meta.mojang.com", "piston-data.mojang.com": break
        case "libraries.minecraft.net": parts.percentEncodedPath = "/libraries" + path
        case "resources.download.minecraft.net": parts.percentEncodedPath = "/assets" + path
        case "maven.minecraftforge.net", "maven.fabricmc.net": parts.percentEncodedPath = "/maven" + path
        case "files.minecraftforge.net": guard path.hasPrefix("/maven/") else { return nil }
        case "maven.neoforged.net":
            guard path.hasPrefix("/releases/") else { return nil }
            parts.percentEncodedPath = "/maven/" + path.dropFirst("/releases/".count)
        case "meta.fabricmc.net": parts.percentEncodedPath = "/fabric-meta" + path
        default: return nil
        }
        parts.host = "bmclapi2.bangbang93.com"; parts.port = nil
        return parts.url
    }
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
