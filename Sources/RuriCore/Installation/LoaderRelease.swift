import Foundation
import RuriLocalization

public enum LoaderReleaseChannel: String, CaseIterable, Sendable, Identifiable {
    case stable, beta, alpha, rc, snapshot, preview
    public var id: Self { self }
    public var title: String {
        switch self {
        case .stable: Messages.LoaderSelection.stable.localized
        case .beta: "Beta"
        case .alpha: "Alpha"
        case .rc: "RC"
        case .snapshot: Messages.LoaderSelection.snapshot.localized
        case .preview: Messages.LoaderSelection.preview.localized
        }
    }

    static func detect(_ version: String, stable: Bool? = nil) -> Self {
        let text = version.lowercased()
        for (token, channel) in [("snapshot", Self.snapshot), ("beta", .beta), ("alpha", .alpha), ("rc", .rc), ("pre", .preview)] {
            if text.range(of: "(?:^|[-_.+])" + token + "(?:[0-9._-]|$)", options: .regularExpression) != nil { return channel }
        }
        return stable == false ? .preview : .stable
    }
}

public struct LoaderRelease: Identifiable, Equatable, Sendable {
    public let version: String
    public let channel: LoaderReleaseChannel
    public let forgeCompatibility: String?
    public var id: String { version }
    public init(version: String, channel: LoaderReleaseChannel? = nil, forgeCompatibility: String? = nil) {
        self.version = version; self.channel = channel ?? .detect(version); self.forgeCompatibility = forgeCompatibility
    }
    public var excludesForge: Bool {
        forgeCompatibility?.range(of: "(?:N/A|none)", options: [.regularExpression, .caseInsensitive]) != nil
    }
    public static func sorted(_ releases: [Self]) -> [Self] {
        var seen = Set<String>()
        return releases.filter { seen.insert($0.version).inserted }.sorted {
            if ($0.channel == .stable) != ($1.channel == .stable) { return $0.channel == .stable }
            return $0.version.compare($1.version, options: [.numeric, .caseInsensitive]) == .orderedDescending
        }
    }
}

enum LoaderReleaseCatalog {
    struct Game: Decodable, Sendable { let version: String }
    struct Entry: Decodable, Sendable {
        struct Version: Decodable, Sendable { let version: String; let stable: Bool? }
        let loader: Version
        let intermediary: Game?
        let hashed: Game?
    }

    static func releases(_ loader: LoaderKind, game: String, client: HTTPClient = .shared) async throws -> [LoaderRelease] {
        guard loader != .vanilla, !game.isEmpty else { return [] }
        if loader == .liteloader {
            return try await LiteLoaderCatalog.releases(game: game, client: client).map {
                LoaderRelease(version: $0.version, channel: $0.snapshot ? .snapshot : .stable)
            }
        }
        if loader == .optifine {
            return try await OptiFineCatalog.releases(game: game, client: client).map {
                LoaderRelease(version: $0.version, forgeCompatibility: $0.forge)
            }
        }
        if loader.usesInstaller {
            return try await ForgeCatalog.versions(loader: loader, game: game, client: client).map { LoaderRelease(version: $0) }
        }
        let target = LoaderEndpoints.metadataGame(game, loader: loader)
        let games = try await client.get([Game].self, from: LoaderEndpoints.games(loader: loader))
        guard games.contains(where: { $0.version == target }) else { return [] }
        let entries = try await client.get([Entry].self, from: LoaderEndpoints.versions(loader: loader, game: game))
        return entries.filter {
            let mapping = ($0.intermediary ?? $0.hashed)?.version
            if mapping == target { return true }
            // For unobfuscated games, Fabric uses a no-op intermediary and Quilt omits mappings.
            // The game catalog above still determines whether the requested game is supported.
            switch loader {
            case .fabric: return mapping == "0.0.0"
            case .quilt: return mapping == nil
            default: return false
            }
        }.map {
            LoaderRelease(version: $0.loader.version, channel: .detect($0.loader.version, stable: $0.loader.stable))
        }
    }
}
