import RuriLocalization
import Foundation

enum LiteLoaderCatalog {
    static let catalogURL = URL(string: "https://dl.liteloader.com/versions/versions.json")!
    static let snapshotsURL = URL(string: "https://repo.mumfrey.com/content/repositories/snapshots/com/mumfrey/liteloader")!
    struct Catalog: Decodable, Sendable { let versions: [String: Game] }
    struct Game: Decodable, Sendable {
        struct Repository: Decodable, Sendable { let url: URL }
        let repo: Repository
        let artefacts: Branch?
        let snapshots: Branch?
    }
    struct Branch: Decodable, Sendable {
        let builds: [String: Build]
        enum CodingKeys: String, CodingKey { case builds = "com.mumfrey:liteloader" }
    }
    struct Build: Decodable, Sendable {
        let version: String
        let file: String
        let tweakClass: String
        let libraries: [Library]
        let md5: String?
    }
    struct Release: Sendable {
        let version: String
        let aliases: [String]
        let url: URL
        let build: Build
        let snapshot: Bool

        func profile(game: String, base: VersionManifest, sha1: String? = nil) throws -> VersionManifest {
            let coordinate = "com.mumfrey:liteloader:" + version
            let path = try Library.mavenPath(coordinate)
            let md5: String?
            if !snapshot, let value = build.md5 {
                guard value.range(of: "^[a-fA-F0-9]{1,32}$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreLiteLoaderCatalog.valueText1) }
                md5 = String(repeating: "0", count: 32 - value.count) + value.lowercased()
            } else { md5 = nil }
            var libraries = try build.libraries.map { library in
                var library = library
                if let url = library.url { library.url = try LiteLoaderCatalog.secureURL(url) }
                return library
            }
            libraries.append(Library(name: coordinate, downloads: .init(artifact: Artifact(path: path, url: url, sha1: sha1, md5: md5)), rules: nil, natives: nil, extract: nil))
            let arguments = ["--tweakClass", build.tweakClass]
            guard build.tweakClass == "com.mumfrey.liteloader.launch.LiteLoaderTweaker" else { throw RuriError.message(Messages.CoreLiteLoaderCatalog.argumentsText1) }
            var profile = VersionManifest(id: game + "-LiteLoader-" + version, mainClass: "net.minecraft.launchwrapper.Launch", libraries: libraries)
            // Older Minecraft versions read minecraftArguments instead of arguments.game.
            if let legacy = base.minecraftArguments {
                profile.minecraftArguments = try ArgumentTokenizer.join(ArgumentTokenizer.split(legacy) + arguments)
            } else { profile.arguments = .init(game: arguments.map(LaunchArgument.text)) }
            return profile
        }
    }

    static func releases(game: String, client: HTTPClient = .shared) async throws -> [Release] {
        let catalog = try await client.get(Catalog.self, from: catalogURL)
        guard let entry = catalog.versions[game] else { return [] }
        var releases = try stableReleases(entry, game: game)
        if let snapshot = entry.snapshots?.builds["latest"] {
            let url = try EndpointURL.build(base: snapshotsURL, path: [game + "-SNAPSHOT", "maven-metadata.xml"])
            let data = try await client.data(from: url)
            let value = try snapshotRelease(snapshot, game: game, metadata: data)
            releases.append(value)
        }
        return releases
    }

    static func profile(game: String, version: String, base: VersionManifest, client: HTTPClient = .shared) async throws -> (VersionManifest, String) {
        let releases = try await releases(game: game, client: client)
        guard let release = releases.first(where: { $0.version == version || $0.aliases.contains(version) }) else { throw RuriError.message(Messages.CoreLiteLoaderCatalog.releaseText1(String(describing: game), String(describing: version))) }
        var sha1: String?
        if release.snapshot {
            let checksum = try await client.data(from: URL(string: release.url.absoluteString + ".sha1")!)
            let value = String(decoding: checksum, as: UTF8.self).split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            guard value.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreLiteLoaderCatalog.valueText2) }
            sha1 = value.lowercased()
        }
        return (try release.profile(game: game, base: base, sha1: sha1), release.version)
    }

    static func stableReleases(_ entry: Game, game: String) throws -> [Release] {
        let builds = entry.artefacts?.builds ?? [:]
        let latest = builds["latest"]?.version
        return try builds.filter { $0.key != "latest" }.map { _, build in
            let url = try EndpointURL.build(base: secureURL(entry.repo.url), path: ["com", "mumfrey", "liteloader", game, build.file])
            return Release(version: build.version, aliases: build.version == latest ? [game] : [], url: url, build: build, snapshot: false)
        }.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    static func snapshotRelease(_ build: Build, game: String, metadata: Data) throws -> Release {
        let reader = SnapshotMetadata(), parser = XMLParser(data: metadata)
        parser.delegate = reader; parser.shouldResolveExternalEntities = false
        guard parser.parse(), let timestamp = reader.values["timestamp"], let number = reader.values["buildNumber"],
              timestamp.range(of: "^[0-9]{8}\\.[0-9]{6}$", options: .regularExpression) != nil,
              number.range(of: "^[0-9]+$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CoreLiteLoaderCatalog.numberText1) }
        let revision = timestamp + "-" + number
        let url = try EndpointURL.build(base: snapshotsURL, path: [game + "-SNAPSHOT", "liteloader-" + game + "-" + revision + "-release.jar"])
        return Release(version: game + "-" + revision, aliases: [game + "-SNAPSHOT", revision], url: url, build: build, snapshot: true)
    }

    private static func secureURL(_ url: URL) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), ["https", "http"].contains(components.scheme),
              components.host != nil, components.user == nil, components.password == nil else { throw RuriError.message(Messages.CoreLiteLoaderCatalog.componentsText1) }
        components.scheme = "https"
        return components.url!
    }

    private final class SnapshotMetadata: NSObject, XMLParserDelegate {
        var values: [String: String] = [:]
        private var path: [String] = []
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) { path.append(elementName) }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if path.count == 4, path.prefix(3).elementsEqual(["metadata", "versioning", "snapshot"]), let key = path.last {
                values[key, default: ""] += string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { path.removeLast() }
    }
}
