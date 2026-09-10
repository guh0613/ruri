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
    public func search(_ query: String, type: String, offset: Int = 0) async throws -> ModrinthSearch {
        try await client.get(ModrinthSearch.self, from: ModrinthEndpoints.search(query, type: type, offset: offset))
    }
    public func versions(project: String, game: String? = nil, loader: String? = nil) async throws -> [ModrinthVersion] {
        try await client.get([ModrinthVersion].self, from: ModrinthEndpoints.versions(project: project, game: game, loader: loader))
    }
    public func install(version: ModrinthVersion, type: String, instance: GameInstance, paths: LauncherPaths, downloader: DownloadManager, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        guard let kind = ContentKind(rawValue: type) else { throw RuriError.message("不支持的内容类型") }
        if type == "mod", instance.loader == .vanilla { throw RuriError.message("模组需要已安装加载器的实例，请先创建相应实例。") }
        var queue = [version]; var resolved: [ModrinthVersion] = []; var seen = Set<String>()
        while !queue.isEmpty {
            try Task.checkCancellation()
            let current = queue.removeFirst()
            if !seen.insert(current.id).inserted { continue }
            if let other = resolved.first(where: { $0.project_id == current.project_id }), other.id != current.id { throw RuriError.message("依赖要求同一项目的不同版本：\(current.name)。请选择其他兼容版本。") }
            guard seen.count <= 200 else { throw RuriError.message("模组依赖数量超出限制") }
            guard current.game_versions.contains(instance.gameVersion) else { throw RuriError.message("\(current.name) 不支持 Minecraft \(instance.gameVersion)") }
            if type == "mod", !current.loaders.contains(instance.loader.rawValue) { throw RuriError.message("\(current.name) 不支持此实例的加载器") }
            resolved.append(current)
            if type == "mod" {
                for dependency in current.dependencies where dependency.dependency_type == "required" {
                    if let id = dependency.version_id {
                        queue.append(try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(id)))
                    } else if let project = dependency.project_id {
                        guard let match = try await versions(project: project, game: instance.gameVersion, loader: instance.loader.rawValue).first else { throw RuriError.message("找不到兼容的必需依赖：\(project)") }
                        queue.append(match)
                    } else { throw RuriError.message("必需依赖缺少下载标识") }
                }
            }
        }
        let staging = paths.cache.appendingPathComponent("content-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [ContentInstallation] = []
        for item in resolved {
            guard let file = item.primaryFile else { throw RuriError.message("\(item.name) 没有可下载的文件") }
            guard file.hashes["sha1"] != nil || file.hashes["sha512"] != nil else { throw RuriError.message("\(file.filename) 缺少校验信息") }
            let temp = try LauncherPaths.safePath("\(item.id)/\(file.filename)", within: staging)
            await progress(InstallProgress("下载 \(file.filename)", completed: files.count, total: resolved.count))
            try await downloader.fetch(DownloadItem(url: file.url, destination: temp, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
            let required = item.dependencies.filter { $0.dependency_type == "required" }.compactMap { dependency in
                dependency.project_id ?? resolved.first(where: { $0.id == dependency.version_id })?.project_id
            }
            let record = ManagedContent(projectID: item.project_id, versionID: item.id, title: item.name, versionName: item.version_number, publishedAt: item.date_published, kind: kind, filename: file.filename, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size, requiredProjects: required)
            files.append(ContentInstallation(record: record, source: temp))
        }
        try Task.checkCancellation()
        await progress(InstallProgress("正在应用内容更新", completed: files.count, total: files.count))
        try await ContentManager(paths: paths, instanceID: instance.id).install(files)
    }
    public func updates(for records: [ManagedContent], instance: GameInstance) async throws -> [ContentUpdate] {
        var updates: [ContentUpdate] = []
        for record in records where record.provider == "modrinth" {
            try Task.checkCancellation()
            let available = try await versions(project: record.projectID, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader.rawValue : nil)
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
