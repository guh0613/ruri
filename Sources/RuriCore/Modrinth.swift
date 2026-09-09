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
    public let files: [File]
    public let dependencies: [Dependency]
    public let game_versions: [String]
    public let loaders: [String]
    public var primaryFile: File? { files.first(where: \.primary) ?? files.first }
}

public actor ModrinthService {
    private let base = URL(string: "https://api.modrinth.com/v2")!
    public init() {}
    public func search(_ query: String, type: String, offset: Int = 0) async throws -> ModrinthSearch {
        var url = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        let facets = String(decoding: try JSONEncoder().encode([["project_type:\(type)"]]), as: UTF8.self)
        url.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "facets", value: facets), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: String(offset)), URLQueryItem(name: "index", value: query.isEmpty ? "downloads" : "relevance")]
        return try await HTTPClient.shared.get(ModrinthSearch.self, from: url.url!)
    }
    public func versions(project: String, game: String? = nil, loader: String? = nil) async throws -> [ModrinthVersion] {
        var url = URLComponents(url: base.appendingPathComponent("project").appendingPathComponent(project).appendingPathComponent("version"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = []
        for (key, value) in [("game_versions", game), ("loaders", loader)] {
            if let value { items.append(URLQueryItem(name: key, value: String(decoding: try JSONEncoder().encode([value]), as: UTF8.self))) }
        }
        url.queryItems = items.isEmpty ? nil : items
        return try await HTTPClient.shared.get([ModrinthVersion].self, from: url.url!)
    }
    public func install(version: ModrinthVersion, type: String, instance: GameInstance, paths: LauncherPaths, downloader: DownloadManager, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let folder = type == "shader" ? "shaderpacks" : type == "resourcepack" ? "resourcepacks" : "mods"
        if type == "mod", instance.loader == .vanilla { throw RuriError.message("模组需要 Fabric 或 Quilt 实例，请先创建相应实例。") }
        var queue = [version]; var resolved: [ModrinthVersion] = []; var seen = Set<String>()
        while !queue.isEmpty {
            try Task.checkCancellation()
            let current = queue.removeFirst()
            if !seen.insert(current.id).inserted { continue }
            guard seen.count <= 200 else { throw RuriError.message("模组依赖数量超出限制") }
            guard current.game_versions.contains(instance.gameVersion) else { throw RuriError.message("\(current.name) 不支持 Minecraft \(instance.gameVersion)") }
            if type == "mod", !current.loaders.contains(instance.loader.rawValue) { throw RuriError.message("\(current.name) 不支持此实例的加载器") }
            resolved.append(current)
            if type == "mod" {
                for dependency in current.dependencies where dependency.dependency_type == "required" {
                    if let id = dependency.version_id {
                        queue.append(try await HTTPClient.shared.get(ModrinthVersion.self, from: base.appendingPathComponent("version").appendingPathComponent(id)))
                    } else if let project = dependency.project_id {
                        guard let match = try await versions(project: project, game: instance.gameVersion, loader: instance.loader.rawValue).first else { throw RuriError.message("找不到兼容的必需依赖：\(project)") }
                        queue.append(match)
                    } else { throw RuriError.message("必需依赖缺少下载标识") }
                }
            }
        }
        let targetRoot = paths.game(instance.id).appendingPathComponent(folder)
        let staging = paths.cache.appendingPathComponent("content-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        var files: [(URL, URL)] = []
        for item in resolved {
            guard let file = item.primaryFile else { throw RuriError.message("\(item.name) 没有可下载的文件") }
            let target = try LauncherPaths.safePath(file.filename, within: targetRoot)
            let temp = try LauncherPaths.safePath(file.filename, within: staging)
            await progress(InstallProgress("下载 \(file.filename)", completed: files.count, total: resolved.count))
            try await downloader.fetch(DownloadItem(url: file.url, destination: temp, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
            files.append((temp, target))
        }
        try Task.checkCancellation()
        for (source, target) in files {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard rename(source.path, target.path) == 0 else { throw RuriError.message("无法安装 \(target.lastPathComponent)") }
        }
    }
}

public struct ModpackIndex: Decodable, Sendable {
    public struct File: Decodable, Sendable {
        public let path: String; public let hashes: [String: String]; public let env: [String: String]?
        public let downloads: [URL]; public let fileSize: Int64
    }
    public let formatVersion: Int
    public let game: String
    public let name: String
    public let versionId: String
    public let dependencies: [String: String]
    public let files: [File]
}

public actor ModpackImporter {
    let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }
    public func install(_ archive: URL, installer: GameInstaller, progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> GameInstance {
        let temp = paths.cache.appendingPathComponent("import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        await progress(InstallProgress("正在读取整合包"))
        try SafeArchive.extract(archive, to: temp)
        let indexURL = temp.appendingPathComponent("modrinth.index.json")
        guard FileManager.default.fileExists(atPath: indexURL.path) else { throw RuriError.message("此文件不是 Modrinth 整合包（缺少 modrinth.index.json）。") }
        let index = try JSONDecoder().decode(ModpackIndex.self, from: Data(contentsOf: indexURL))
        guard index.formatVersion == 1, index.game == "minecraft", let game = index.dependencies["minecraft"] else { throw RuriError.message("不支持的整合包格式或游戏") }
        let supported = Set(["minecraft", "fabric-loader", "quilt-loader"])
        let unknown = Set(index.dependencies.keys).subtracting(supported)
        guard unknown.isEmpty else { throw RuriError.message("此整合包需要 \(unknown.sorted().joined(separator: ", "))，目前尚未接入该加载器。") }
        let loader: LoaderKind = index.dependencies["fabric-loader"] != nil ? .fabric : index.dependencies["quilt-loader"] != nil ? .quilt : .vanilla
        var instance = GameInstance(name: index.name, gameVersion: game, loader: loader, loaderVersion: index.dependencies["fabric-loader"] ?? index.dependencies["quilt-loader"])
        do {
            instance = try await installer.install(instance, progress: progress)
            let files = try index.files.filter { $0.env?["client"] != "unsupported" }.map { file -> DownloadItem in
                guard let url = file.downloads.first(where: { $0.scheme == "https" }) else { throw RuriError.message("整合包文件缺少 HTTPS 下载地址：\(file.path)") }
                guard file.hashes["sha1"] != nil || file.hashes["sha512"] != nil else { throw RuriError.message("整合包文件缺少校验哈希：\(file.path)") }
                return DownloadItem(url: url, destination: try LauncherPaths.safePath(file.path, within: paths.game(instance.id)), sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.fileSize)
            }
            try await installer.downloader.download(files) { done, total in await progress(InstallProgress("正在安装整合包内容", completed: done, total: total)) }
            for folder in ["overrides", "client-overrides"] {
                let source = temp.appendingPathComponent(folder)
                guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { continue }
                while let file = enumerator.nextObject() as? URL {
                    try Task.checkCancellation()
                    guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    let relative = String(file.path.dropFirst(source.path.count + 1))
                    let target = try LauncherPaths.safePath(relative, within: paths.game(instance.id))
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(contentsOf: file).write(to: target, options: .atomic)
                }
            }
            return instance
        } catch { try? FileManager.default.removeItem(at: paths.instance(instance.id)); throw error }
    }
}
