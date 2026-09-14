import Foundation
import RuriLocalization

public enum CatalogSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case modrinth = "Modrinth", curseforge = "CurseForge"
    public var id: String { rawValue }
}
public enum CatalogSort: String, CaseIterable, Identifiable, Sendable, Codable {
    case relevance, downloads, updated, newest
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .relevance: Messages.Discovery.relevance.localized
        case .downloads: Messages.Discovery.mostDownloads.localized
        case .updated: Messages.Discovery.recentlyUpdated.localized
        case .newest: Messages.Discovery.newest.localized
        }
    }
    var modrinthIndex: String { rawValue }
    var curseForgeField: Int { switch self { case .relevance: 2; case .downloads: 6; case .updated: 3; case .newest: 11 } }
}
public struct CatalogQuery: Hashable, Sendable {
    public var source: CatalogSource = .modrinth
    public var type = "modpack"
    public var text = ""
    public var game = ""
    public var loader = ""
    public var category = ""
    public var sort: CatalogSort = .downloads
    public var offset = 0
    public init() {}
    public var hasFilters: Bool { !game.isEmpty || !loader.isEmpty || !category.isEmpty }
    public var normalized: Self {
        var value = self
        value.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value.game = game.trimmingCharacters(in: .whitespacesAndNewlines)
        value.offset = max(0, offset)
        if type != "mod" && type != "modpack" { value.loader = "" }
        if source == .curseforge && sort == .relevance { value.sort = .downloads }
        return value
    }
}
public enum CatalogMetadata {
    public static let loaderNames = ["fabric", "forge", "neoforge", "quilt", "legacy-fabric", "liteloader", "iris", "optifine", "canvas", "vanilla"]
    public static func webURL(_ string: String) -> URL? {
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func loaderTitle(_ value: String) -> String {
        LoaderKind.allCases.first { $0.modrinthLoader == value }?.title ?? (value == "iris" ? "Iris" : value.capitalized)
    }
    public static func curseForgeLoaderID(_ value: String) -> Int? {
        ["forge": 1, "liteloader": 3, "fabric": 4, "legacy-fabric": 4, "quilt": 5, "neoforge": 6][value]
    }
    public static func curseForgeLoader(_ id: Int?) -> String? {
        guard let id else { return nil }
        return [1: "forge", 3: "liteloader", 4: "fabric", 5: "quilt", 6: "neoforge"][id]
    }
    public static func sortedVersions(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.compare($1, options: .numeric) == .orderedDescending }
    }
    public static func versionSummary(_ values: [String]) -> String {
        let stable = values.filter { $0.range(of: #"^[0-9]+(?:\.[0-9]+)+$"#, options: .regularExpression) != nil }
        let versions = sortedVersions(stable.isEmpty ? values : stable)
        guard !versions.isEmpty else { return Messages.Discovery.versionsUnknown.localized }
        // Do not imply support for every release between two endpoints.
        return versions.prefix(3).joined(separator: ", ") + (versions.count > 3 ? " +\(versions.count - 3)" : "")
    }
}
public enum CatalogProject: Identifiable, Sendable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    case modrinth(ModrinthProject), curseforge(CurseForgeProject)
    public var id: String { source.rawValue + ":" + projectID }
    public var source: CatalogSource { switch self { case .modrinth: .modrinth; case .curseforge: .curseforge } }
    public var projectID: String { switch self { case .modrinth(let p): p.id; case .curseforge(let p): String(p.id) } }
    public var title: String { switch self { case .modrinth(let p): p.title; case .curseforge(let p): p.name } }
    public var author: String { switch self { case .modrinth(let p): p.author; case .curseforge(let p): p.authors?.map(\.name).joined(separator: ", ") ?? Messages.AppDiscoverView.communityAuthor.localized } }
    public var summary: String { switch self { case .modrinth(let p): p.description; case .curseforge(let p): p.summary } }
    public var icon: URL? { switch self { case .modrinth(let p): p.icon_url; case .curseforge(let p): p.logo?.thumbnailUrl } }
    public var downloads: Double { switch self { case .modrinth(let p): Double(p.downloads); case .curseforge(let p): p.downloadCount } }
    public var type: String { switch self { case .modrinth(let p): p.project_type; case .curseforge(let p): p.contentType ?? "mod" } }
    public var gameVersions: [String] { switch self { case .modrinth(let p): p.gameVersions; case .curseforge(let p): CatalogMetadata.sortedVersions(p.latestFilesIndexes?.map(\.gameVersion) ?? []) } }
    public var loaders: [String] { switch self { case .modrinth(let p): p.loaders; case .curseforge(let p): Array(Set(p.latestFilesIndexes?.compactMap { CatalogMetadata.curseForgeLoader($0.modLoader) } ?? [])).sorted() } }
    public var categories: [String] { switch self { case .modrinth(let p): p.categories.filter { !CatalogMetadata.loaderNames.contains($0) }; case .curseforge(let p): p.categories?.map(\.name) ?? [] } }
    public var pageURL: URL? { switch self { case .modrinth(let p): p.pageURL; case .curseforge(let p): p.links?.websiteUrl } }
    public var updated: String? { switch self { case .modrinth(let p): p.updated; case .curseforge(let p): p.dateModified } }
}
public struct CatalogPage: Sendable {
    public let projects: [CatalogProject]
    public let total: Int
    public init(projects: [CatalogProject], total: Int) { self.projects = projects; self.total = total }
}
public struct ModrinthCategory: Decodable, Sendable { public let name: String; public let project_type: String; public let header: String? }
public struct CurseForgeCategory: Decodable, Sendable { public let id: Int; public let name: String; public let classId: Int?; public let parentCategoryId: Int? }
public struct CatalogCategory: Identifiable, Sendable { public let id: String; public let name: String; public let type: String }
public struct CatalogGalleryImage: Identifiable, Sendable {
    public var id: String { url.absoluteString }
    public let url: URL
    public let title: String?
}
public struct CatalogLink: Identifiable, Sendable {
    public var id: String { url.absoluteString }
    public let title: String
    public let symbol: String
    public let url: URL
}
public struct CatalogDetail: Sendable {
    public let project: CatalogProject
    public let body: String
    public let isHTML: Bool
    public let gallery: [CatalogGalleryImage]
    public let links: [CatalogLink]
    public let license: String?
}
public enum CatalogVersion: Identifiable, Sendable {
    case modrinth(ModrinthVersion), curseforge(CurseForgeFile)
    public var id: String { switch self { case .modrinth(let v): v.id; case .curseforge(let f): String(f.id) } }
    public var name: String { switch self { case .modrinth(let v): v.name; case .curseforge(let f): f.displayName } }
    public var number: String { switch self { case .modrinth(let v): v.version_number; case .curseforge(let f): f.displayName } }
    public var gameVersions: [String] { switch self { case .modrinth(let v): v.game_versions; case .curseforge(let f): f.gameVersions.filter { $0.first?.isNumber == true || $0.hasPrefix("b1.") || $0.hasPrefix("a1.") } } }
    public var loaders: [String] { switch self { case .modrinth(let v): v.loaders; case .curseforge(let f): f.gameVersions.map { $0.lowercased() }.filter { CatalogMetadata.loaderNames.contains($0) } } }
    public var published: String { switch self { case .modrinth(let v): v.date_published ?? ""; case .curseforge(let f): f.fileDate } }
    public var channel: String { switch self { case .modrinth(let v): v.version_type ?? "release"; case .curseforge(let f): f.releaseType == 2 ? "beta" : f.releaseType == 3 ? "alpha" : "release" } }
    public var filename: String { switch self { case .modrinth(let v): v.primaryFile?.filename ?? v.name; case .curseforge(let f): f.fileName } }
    public var size: Int64 { switch self { case .modrinth(let v): v.primaryFile?.size ?? 0; case .curseforge(let f): f.fileLength } }
    public var dependencies: [CatalogDependency] {
        switch self {
        case .modrinth(let v): v.dependencies.enumerated().map { index, d in CatalogDependency(id: "\(index)", source: .modrinth, projectID: d.project_id, versionID: d.version_id, relation: d.dependency_type) }
        case .curseforge(let f): f.dependencies.enumerated().map { index, d in CatalogDependency(id: "\(index)", source: .curseforge, projectID: String(d.modId), versionID: nil, relation: [1: "embedded", 2: "optional", 3: "required", 4: "tool", 5: "incompatible", 6: "include"][d.relationType] ?? "optional") }
        }
    }
    public func supports(_ instance: GameInstance, type: String) -> Bool {
        switch self {
        case .modrinth(let v): v.game_versions.contains(instance.gameVersion) && (type != "mod" || (instance.loader != .vanilla && v.loaders.contains(instance.loader.modrinthLoader)))
        case .curseforge(let f): ContentKind(rawValue: type).map { f.supports(instance, kind: $0) } ?? false
        }
    }
}
public struct CatalogDependency: Identifiable, Sendable {
    public let id: String
    public let source: CatalogSource
    public let projectID: String?
    public let versionID: String?
    public let relation: String
    public var title: String {
        switch relation {
        case "required": Messages.Discovery.required.localized
        case "optional": Messages.Discovery.optional.localized
        case "incompatible": Messages.Discovery.incompatible.localized
        case "embedded", "include": Messages.Discovery.embedded.localized
        default: Messages.Discovery.tool.localized
        }
    }
}
public struct CatalogVersionPage: Sendable { public let versions: [CatalogVersion]; public let total: Int }
