import RuriLocalization
import Foundation

public struct WorldDataPackDownloadPlan: Identifiable, Sendable {
    public let id = UUID()
    public let gameVersion: String
    public let versions: [ModrinthVersion]
    public let files: [ModrinthVersion.File]
    public var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

public actor WorldDataPackDownloads {
    private let client: HTTPClient
    private let modrinth: ModrinthService
    public init(client: HTTPClient = .shared) { self.client = client; modrinth = ModrinthService(client: client) }
    public func search(_ query: String, game: String, offset: Int = 0) async throws -> ModrinthSearch {
        try await modrinth.search(query, type: "datapack", offset: offset, game: game)
    }
    public func versions(project: String, game: String) async throws -> [ModrinthVersion] {
        try await modrinth.versions(project: project, game: game, loader: "datapack").filter {
            $0.game_versions.contains(game) && $0.loaders.contains("datapack") && $0.files.contains { $0.filename.lowercased().hasSuffix(".zip") }
        }
    }
    public func prepare(_ version: ModrinthVersion, game: String) async throws -> WorldDataPackDownloadPlan {
        var queue = [version], resolved: [ModrinthVersion] = [], seen = Set<String>()
        while !queue.isEmpty {
            try Task.checkCancellation()
            let item = queue.removeFirst()
            if !seen.insert(item.id).inserted { continue }
            guard seen.count <= 200 else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.tooManyDataPackDependencies) }
            guard item.game_versions.contains(game), item.loaders.contains("datapack") else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.noDataPackVersionForGame(item.name, String(describing: game))) }
            guard !resolved.contains(where: { $0.project_id == item.project_id && $0.id != item.id }) else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.conflictingDataPackVersions) }
            resolved.append(item)
            for dependency in item.dependencies where dependency.dependency_type == "required" {
                if let id = dependency.version_id {
                    if let known = (resolved + queue).first(where: { $0.id == id }) { queue.append(known) }
                    else { queue.append(try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(id))) }
                } else if let project = dependency.project_id {
                    if let known = (resolved + queue).first(where: { $0.project_id == project }) { queue.append(known); continue }
                    let versions = try await versions(project: project, game: game)
                    guard let match = versions.first(where: { $0.version_type == "release" || $0.version_type == nil }) ?? versions.first else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.compatibleDataPackMissing(String(describing: project))) }
                    queue.append(match)
                } else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.incompleteRequiredDependency) }
            }
        }
        for item in resolved {
            for dependency in item.dependencies where dependency.dependency_type == "incompatible" {
                if resolved.contains(where: { other in dependency.version_id.map { $0 == other.id } ?? (dependency.project_id == other.project_id) }) {
                    throw RuriError.message(Messages.CoreWorldDataPackDownloads.incompatibleRequiredDependency(item.name))
                }
            }
        }
        let files = try resolved.map { item in
            let archives = item.files.filter { $0.filename.lowercased().hasSuffix(".zip") }
            guard let file = archives.first(where: \.primary) ?? archives.first,
                  !file.filename.contains("/"), !file.filename.contains("\\"), !file.filename.hasPrefix("."), (1...536_870_912).contains(file.size),
                  file.url.scheme == "https", file.url.host != nil, file.url.user == nil, file.url.password == nil,
                  file.hashes["sha1"]?.range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil || file.hashes["sha512"]?.range(of: "^[a-fA-F0-9]{128}$", options: .regularExpression) != nil else {
                throw RuriError.message(Messages.CoreWorldDataPackDownloads.missingDataPackArchive(item.name))
            }
            return file
        }
        guard Set(files.map { $0.filename.lowercased() }).count == files.count else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.duplicateDataPackFilename) }
        return WorldDataPackDownloadPlan(gameVersion: game, versions: resolved, files: files)
    }
    public func install(_ plan: WorldDataPackDownloadPlan, instance: GameInstance, folder: String, paths: LauncherPaths, downloader: DownloadManager,
                        progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let state = try StateStore.load(paths)
        guard let current = state.instances.first(where: { $0.id == instance.id }), current.gameVersion == plan.gameVersion else { throw RuriError.message(Messages.CoreWorldDataPackDownloads.gameVersionChanged) }
        _ = try current.applyingInstallation(instance, requested: instance)
        try paths.validateBinding(current)
        var sources: [URL] = []
        for (version, file) in zip(plan.versions, plan.files) {
            let destination = try LauncherPaths.safePath("datapacks/\(version.id)/\(file.filename)", within: paths.cache)
            await progress(InstallProgress(Messages.CoreWorldDataPackDownloads.downloadDataPack(version.name), completed: sources.count, total: plan.files.count))
            try await downloader.fetch(DownloadItem(url: file.url, destination: destination, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
            sources.append(destination)
        }
        try Task.checkCancellation()
        await progress(InstallProgress(Messages.CoreWorldDataPackDownloads.importingDataPack))
        // Put the requested pack after its dependencies so it can override them.
        try await WorldManager(paths: paths, instanceID: instance.id).importDataPacks(from: sources.reversed(), folder: folder)
    }
}
