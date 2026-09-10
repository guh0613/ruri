import Foundation

enum LoaderEndpoints {
    private static let fabric = URL(string: "https://meta.fabricmc.net/v2/versions/loader")!
    private static let quilt = URL(string: "https://meta.quiltmc.org/v3/versions/loader")!
    private static let legacyFabric = URL(string: "https://meta.legacyfabric.net/v2/versions/loader")!
    static let legacyFabricGames = URL(string: "https://meta.legacyfabric.net/v2/versions/game")!
    private static let forge = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge")!
    private static let neoForge = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge")!
    private static let legacyNeoForge = URL(string: "https://maven.neoforged.net/releases/net/neoforged/forge")!

    private static func profileService(_ loader: LoaderKind) throws -> URL {
        switch loader {
        case .fabric: fabric
        case .quilt: quilt
        case .legacyfabric: legacyFabric
        default: throw RuriError.message("此加载器不提供 Fabric/Quilt 启动清单。")
        }
    }
    static func versions(loader: LoaderKind, game: String) throws -> URL {
        try EndpointURL.build(base: profileService(loader), path: [metadataGame(game, loader: loader)])
    }
    static func profile(loader: LoaderKind, game: String, version: String) throws -> URL {
        try EndpointURL.build(base: profileService(loader), path: [metadataGame(game, loader: loader), version, "profile", "json"])
    }
    static func metadataGame(_ game: String, loader: LoaderKind) -> String {
        loader == .legacyfabric && game.hasPrefix("2.0_") ? "2point0_" + game.dropFirst(4) : game
    }
    static func repository(loader: LoaderKind, game: String) -> URL {
        loader == .forge ? forge : game == "1.20.1" ? legacyNeoForge : neoForge
    }
    static func mavenMetadata(loader: LoaderKind, game: String) -> URL {
        repository(loader: loader, game: game).appending(component: "maven-metadata.xml")
    }
    static func installer(loader: LoaderKind, game: String, version: String) throws -> URL {
        guard loader.usesInstaller else { throw RuriError.message("此加载器不使用 Forge 安装包。") }
        let legacyName = loader == .forge || game == "1.20.1"
        let coordinate = legacyName ? "\(game)-\(version)" : version
        let artifact = legacyName ? "forge" : "neoforge"
        return try EndpointURL.build(base: repository(loader: loader, game: game), path: [coordinate, "\(artifact)-\(coordinate)-installer.jar"])
    }
    static func installerChecksum(_ installer: URL) -> URL { installer.appendingPathExtension("sha1") }
}
