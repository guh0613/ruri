import Foundation

/// MCIM (mod.mcimirror.top) mirrors the public CurseForge and Modrinth file CDNs
/// with identical paths. API hosts are never mirrored; downloads are still
/// verified against the provider's hashes.
enum MCIMEndpoints {
    static let host = "mod.mcimirror.top"
    static func mirror(_ url: URL) -> URL? {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch parts.host?.lowercased() {
        case "edge.forgecdn.net", "cdn.modrinth.com": break
        default: return nil
        }
        parts.host = host; parts.port = nil
        return parts.url
    }
}
