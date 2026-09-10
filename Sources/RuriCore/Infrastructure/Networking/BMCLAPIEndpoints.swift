import Foundation

enum BMCLAPIEndpoints {
    static let host = "bmclapi2.bangbang93.com"
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
        parts.host = host; parts.port = nil
        return parts.url
    }
}
