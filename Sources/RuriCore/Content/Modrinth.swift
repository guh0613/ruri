import Foundation

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
    public func search(_ query: String, type: String, offset: Int = 0, game: String? = nil) async throws -> ModrinthSearch {
        try await client.get(ModrinthSearch.self, from: ModrinthEndpoints.search(query, type: type, offset: offset, game: game))
    }
    public func versions(project: String, game: String? = nil, loader: String? = nil) async throws -> [ModrinthVersion] {
        try await client.get([ModrinthVersion].self, from: ModrinthEndpoints.versions(project: project, game: game, loader: loader))
    }
    public func install(version: ModrinthVersion, type: String, instance: GameInstance, paths: LauncherPaths, downloader: DownloadManager, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        guard let kind = ContentKind(rawValue: type) else { throw RuriError.message("不支持的内容类型") }
        let plan = try await plan(versions: [version], kind: kind, instance: instance)
        let files = try await materialize(plan, paths: paths, downloader: downloader, progress: progress)
        try Task.checkCancellation()
        await progress(InstallProgress("正在应用内容更新", completed: files.count, total: files.count))
        try await ContentManager(paths: paths, instanceID: instance.id).install(files)
    }
    public func updates(for records: [ManagedContent], instance: GameInstance) async throws -> [ContentUpdate] {
        var updates: [ContentUpdate] = []
        for record in records where record.provider == "modrinth" {
            try Task.checkCancellation()
            let available = try await versions(project: record.projectID, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader.modrinthLoader : nil)
            guard let candidate = available.first(where: { $0.version_type == "release" || $0.version_type == nil }), candidate.id != record.versionID else { continue }
            let currentDate: String?
            if let date = record.publishedAt { currentDate = date }
            else { currentDate = try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(record.versionID)).date_published }
            if let currentDate, let newer = candidate.date_published, Self.date(newer) > Self.date(currentDate) { updates.append(ContentUpdate(installed: record, available: candidate)) }
        }
        return updates
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
            guard prepared.format == "Modrinth" else { throw RuriError.message("此文件不是 Modrinth 整合包") }
            let result = try await transfer.install(prepared, name: prepared.instance.name, installer: installer, progress: progress)
            await transfer.discard(prepared); return result
        } catch { await transfer.discard(prepared); throw error }
    }
}
