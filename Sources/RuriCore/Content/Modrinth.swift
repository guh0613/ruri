import RuriLocalization
import Foundation

/// Search hits and project details have different ID and version fields.
/// Optional presentation metadata must never prevent an entire page from decoding.
public struct ModrinthProject: Decodable, Identifiable, Sendable {
    public var id: String { project_id }
    public let project_id: String
    public let slug: String
    public let title: String
    public let description: String
    public let author: String
    public let downloads: Int
    public let icon_url: URL?
    public let project_type: String
    public let categories: [String]
    public let gameVersions: [String]
    public let loaders: [String]
    public let body: String?
    public let updated: String?
    public let published: String?
    public let license: License?
    public let source_url: URL?
    public let issues_url: URL?
    public let wiki_url: URL?
    public let discord_url: URL?
    public let client_side: String?
    public let server_side: String?
    public let gallery: [Gallery]
    public struct License: Decodable, Sendable { public let id: String; public let name: String? }
    public struct Gallery: Decodable, Sendable { public let url: URL; public let title: String?; public let description: String?; public let featured: Bool? }
    private enum CodingKeys: String, CodingKey {
        case id, project_id, slug, title, description, author, downloads, icon_url, project_type, categories, versions, game_versions, loaders
        case body, updated, published, date_modified, date_created, license, source_url, issues_url, wiki_url, discord_url, client_side, server_side, gallery
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let searchID = try c.decodeIfPresent(String.self, forKey: .project_id)
        project_id = try searchID ?? c.decode(String.self, forKey: .id)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? project_id
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? Messages.AppDiscoverView.communityAuthor.localized
        downloads = try c.decodeIfPresent(Int.self, forKey: .downloads) ?? 0
        icon_url = (try? c.decodeIfPresent(String.self, forKey: .icon_url)).flatMap(CatalogMetadata.webURL)
        project_type = try c.decode(String.self, forKey: .project_type)
        categories = try c.decodeIfPresent([String].self, forKey: .categories) ?? []
        gameVersions = try c.decodeIfPresent([String].self, forKey: searchID == nil ? .game_versions : .versions) ?? []
        loaders = try c.decodeIfPresent([String].self, forKey: .loaders) ?? categories.filter { CatalogMetadata.loaderNames.contains($0) }
        body = try c.decodeIfPresent(String.self, forKey: .body)
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? c.decodeIfPresent(String.self, forKey: .date_modified)
        published = try c.decodeIfPresent(String.self, forKey: .published) ?? c.decodeIfPresent(String.self, forKey: .date_created)
        license = try? c.decodeIfPresent(License.self, forKey: .license)
        source_url = (try? c.decodeIfPresent(String.self, forKey: .source_url)).flatMap(CatalogMetadata.webURL)
        issues_url = (try? c.decodeIfPresent(String.self, forKey: .issues_url)).flatMap(CatalogMetadata.webURL)
        wiki_url = (try? c.decodeIfPresent(String.self, forKey: .wiki_url)).flatMap(CatalogMetadata.webURL)
        discord_url = (try? c.decodeIfPresent(String.self, forKey: .discord_url)).flatMap(CatalogMetadata.webURL)
        client_side = try c.decodeIfPresent(String.self, forKey: .client_side)
        server_side = try c.decodeIfPresent(String.self, forKey: .server_side)
        gallery = (try? c.decodeIfPresent([Gallery].self, forKey: .gallery)) ?? []
    }
}
public struct ModrinthSearch: Decodable, Sendable { public let hits: [ModrinthProject]; public let total_hits: Int }
public struct ModrinthVersion: Decodable, Identifiable, Sendable {
    public struct File: Decodable, Sendable { public let url: URL; public let filename: String; public let primary: Bool; public let size: Int64; public let hashes: [String: String] }
    public struct Dependency: Decodable, Sendable { public let version_id: String?; public let project_id: String?; public let dependency_type: String }
    public let id: String
    public let project_id: String
    public let name: String
    public let version_number: String
    public let date_published: String?
    public let version_type: String?
    public var changelog: String? = nil
    public let files: [File]
    public let dependencies: [Dependency]
    public let game_versions: [String]
    public let loaders: [String]
    public var primaryFile: File? { files.first(where: \.primary) ?? files.first }
}

public struct ContentUpdate: Identifiable, Sendable {
    public var id: String { installed.id }
    public let installed: ManagedContent
    public let available: ModrinthVersion
}

public actor ModrinthService {
    let client: HTTPClient
    public init(client: HTTPClient = .shared) { self.client = client }
    public func search(_ query: String, type: String, offset: Int = 0, game: String? = nil, loader: String? = nil, category: String? = nil, sort: CatalogSort? = nil) async throws -> ModrinthSearch {
        try await client.get(ModrinthSearch.self, from: ModrinthEndpoints.search(query, type: type, offset: offset, game: game, loader: loader, category: category, sort: sort))
    }
    public func project(_ id: String) async throws -> ModrinthProject {
        try await client.get(ModrinthProject.self, from: ModrinthEndpoints.project(id))
    }
    public func projects(_ ids: [String]) async throws -> [ModrinthProject] {
        guard !ids.isEmpty else { return [] }
        return try await client.get([ModrinthProject].self, from: ModrinthEndpoints.projects(ids))
    }
    public func version(_ id: String) async throws -> ModrinthVersion {
        try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(id))
    }
    public func categories() async throws -> [ModrinthCategory] {
        try await client.get([ModrinthCategory].self, from: ModrinthEndpoints.categories)
    }
    public func versions(project: String, game: String? = nil, loader: String? = nil) async throws -> [ModrinthVersion] {
        try await client.get([ModrinthVersion].self, from: ModrinthEndpoints.versions(project: project, game: game, loader: loader))
    }
    public func install(version: ModrinthVersion, type: String, instance: GameInstance, paths: LauncherPaths, downloader: DownloadManager, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        guard let kind = ContentKind(rawValue: type) else { throw RuriError.message(Messages.CoreModrinth.unsupportedContentType) }
        let plan = try await plan(versions: [version], kind: kind, instance: instance)
        let files = try await materialize(plan, paths: paths, downloader: downloader, progress: progress)
        try Task.checkCancellation()
        await progress(InstallProgress(Messages.CoreModrinth.applyingContentUpdate, completed: files.count, total: files.count))
        try await ContentManager(paths: paths, instanceID: instance.id).install(files)
    }
    public func updates(for records: [ManagedContent], instance: GameInstance) async throws -> [ContentUpdate] {
        let result = try await ContentUpdateQueries.run(records.filter { $0.provider == "modrinth" }) { record in
            try await self.update(for: record, instance: instance)
        }
        if let failure = result.failures.first { throw failure.underlying }
        return result.updates
    }
    func update(for record: ManagedContent, instance: GameInstance) async throws -> ContentUpdate? {
        try Task.checkCancellation()
        let available = try await versions(project: record.projectID, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader.modrinthLoader : nil)
        guard let candidate = available.first(where: { $0.version_type == "release" || $0.version_type == nil }), candidate.id != record.versionID else { return nil }
        let currentDate: String?
        if let date = record.publishedAt { currentDate = date }
        else { currentDate = try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(record.versionID)).date_published }
        guard let currentDate, let newer = candidate.date_published, Self.date(newer) > Self.date(currentDate) else { return nil }
        return ContentUpdate(installed: record, available: candidate)
    }
    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? .distantPast
    }
}

public struct ModpackIndex: Codable, Sendable {
    public struct File: Codable, Sendable {
        public let path: String; public let hashes: [String: String]; public let env: [String: String]?
        public let downloads: [URL]; public let fileSize: Int64
    }
    public let formatVersion: Int
    public let game: String
    public let name: String
    public let versionId: String
    public var summary: String?
    public let dependencies: [String: String]
    public let files: [File]
}

public actor ModpackImporter {
    let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public func install(_ archive: URL, installer: GameInstaller, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> GameInstance {
        let transfer = InstanceTransfer(paths: paths)
        let prepared = try await transfer.prepare(archive)
        do {
            guard prepared.format == "Modrinth" else { throw RuriError.message(Messages.CoreModrinth.notModrinthPack) }
            let result = try await transfer.install(prepared, name: prepared.instance.name, installer: installer, progress: progress)
            await transfer.discard(prepared); return result
        } catch { await transfer.discard(prepared); throw error }
    }
}
