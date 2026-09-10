import Foundation

public struct PlannedModrinthFile: Sendable {
    public let record: ManagedContent
    public let file: ModrinthVersion.File
}

extension ModrinthService {
    public func plan(versions roots: [ModrinthVersion], kind: ContentKind, instance: GameInstance) async throws -> [PlannedModrinthFile] {
        if kind == .mod, instance.loader == .vanilla { throw RuriError.message("模组需要已安装加载器的实例，请先创建相应实例。") }
        var queue = roots, resolved: [ModrinthVersion] = [], seen = Set<String>()
        while !queue.isEmpty {
            try Task.checkCancellation()
            let current = queue.removeFirst()
            if !seen.insert(current.id).inserted { continue }
            if let other = resolved.first(where: { $0.project_id == current.project_id }), other.id != current.id { throw RuriError.message("依赖要求同一项目的不同版本：\(current.name)。请选择其他兼容版本。") }
            guard seen.count <= 200 else { throw RuriError.message("模组依赖数量超出限制") }
            guard current.game_versions.contains(instance.gameVersion) else { throw RuriError.message("\(current.name) 不支持 Minecraft \(instance.gameVersion)") }
            if kind == .mod, !current.loaders.contains(instance.loader.modrinthLoader) { throw RuriError.message("\(current.name) 不支持此实例的加载器") }
            resolved.append(current)
            if kind == .mod {
                for dependency in current.dependencies where dependency.dependency_type == "required" {
                    if let id = dependency.version_id {
                        if let selected = (roots + resolved + queue).first(where: { $0.id == id }) { queue.append(selected) }
                        else { queue.append(try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(id))) }
                    } else if let project = dependency.project_id {
                        if let selected = (roots + resolved + queue).first(where: { $0.project_id == project }) { queue.append(selected); continue }
                        let options = try await versions(project: project, game: instance.gameVersion, loader: instance.loader.modrinthLoader)
                        guard let match = options.first(where: { $0.version_type == "release" || $0.version_type == nil }) ?? options.first else { throw RuriError.message("找不到兼容的必需依赖：\(project)") }
                        queue.append(match)
                    } else { throw RuriError.message("必需依赖缺少下载标识") }
                }
            }
        }
        for item in resolved {
            for dependency in item.dependencies where dependency.dependency_type == "incompatible" {
                if resolved.contains(where: { other in dependency.version_id.map { $0 == other.id } ?? (dependency.project_id == other.project_id) }) {
                    throw RuriError.message("\(item.name) 与本次选择的其他内容不兼容。")
                }
            }
        }
        return try resolved.map { item in
            guard let file = item.primaryFile else { throw RuriError.message("\(item.name) 没有可下载的文件") }
            guard file.hashes["sha1"] != nil || file.hashes["sha512"] != nil else { throw RuriError.message("\(file.filename) 缺少校验信息") }
            let required = kind == .mod ? item.dependencies.filter { $0.dependency_type == "required" }.compactMap { dependency in
                dependency.project_id ?? resolved.first(where: { $0.id == dependency.version_id })?.project_id
            } : []
            let record = ManagedContent(projectID: item.project_id, versionID: item.id, title: item.name, versionName: item.version_number, publishedAt: item.date_published, kind: kind, filename: file.filename, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size, requiredProjects: required)
            return PlannedModrinthFile(record: record, file: file)
        }
    }

    public func materialize(_ plan: [PlannedModrinthFile], paths: LauncherPaths, downloader: DownloadManager,
                            progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> [ContentInstallation] {
        var result: [ContentInstallation] = []
        for item in plan {
            try Task.checkCancellation()
            let destination = try LauncherPaths.safePath("modrinth/\(item.record.versionID)/\(item.file.filename)", within: paths.cache)
            await progress(InstallProgress("下载 \(item.file.filename)", completed: result.count, total: plan.count))
            try await downloader.fetch(DownloadItem(url: item.file.url, destination: destination, sha1: item.record.sha1, sha512: item.record.sha512, size: item.record.size))
            result.append(ContentInstallation(record: item.record, source: destination))
        }
        return result
    }
}
