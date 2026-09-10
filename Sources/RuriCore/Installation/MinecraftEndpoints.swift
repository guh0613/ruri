import Foundation

/// Mojang bootstrap locations. Artifact URLs supplied by manifests keep their
/// original location; the routing layer chooses any supported mirror later.
enum MinecraftEndpoints {
    private static let metadata = URL(string: "https://piston-meta.mojang.com")!
    static let versionManifest = metadata.appending(path: "mc/game/version_manifest_v2.json")
    // This identifier names Mojang's runtime catalog, not a selected Java version.
    static let javaRuntimeCatalog = metadata.appending(path: "v1/products/java-runtime/2ec0cc96c44e5a76b9c8b7c39df7210883d12871/all.json")
    static let libraries = URL(string: "https://libraries.minecraft.net/")!
    private static let assets = URL(string: "https://resources.download.minecraft.net")!

    static func asset(hash: String) throws -> URL {
        guard hash.utf8.count == 40, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw RuriError.message("资源索引包含无效哈希") }
        return try EndpointURL.build(base: assets, path: [String(hash.prefix(2)), hash])
    }
}
