import RuriLocalization
import Foundation

public struct PlannedModrinthFile: Sendable {
    public let record: ManagedContent
    public let file: ModrinthVersion.File
}

extension ModrinthService {
    public func plan(versions roots: [ModrinthVersion], kind: ContentKind, instance: GameInstance, installed: [ManagedContent] = []) async throws -> [PlannedModrinthFile] {
        if kind == .mod, instance.loader == .vanilla { throw RuriError.message(Messages.CoreModrinthContentPlan.loaderInstanceRequired) }
        var queue = roots, resolved: [ModrinthVersion] = [], seen = Set<String>()
        while !queue.isEmpty {
            try Task.checkCancellation()
            let current = queue.removeFirst()
            if !seen.insert(current.id).inserted { continue }
            if let other = resolved.first(where: { $0.project_id == current.project_id }), other.id != current.id { throw RuriError.message(Messages.CoreModrinthContentPlan.incompatibleProjectVersions(current.name)) }
            guard seen.count <= 200 else { throw RuriError.message(Messages.CoreModrinthContentPlan.dependencyLimitExceeded) }
            guard current.game_versions.contains(instance.gameVersion) else { throw RuriError.message(Messages.CoreModrinthContentPlan.minecraftVersionUnsupported(current.name, instance.gameVersion)) }
            if kind == .mod, !current.loaders.contains(instance.loader.modrinthLoader) { throw RuriError.message(Messages.CoreModrinthContentPlan.loaderUnsupported(current.name)) }
            resolved.append(current)
            if kind == .mod {
                for dependency in current.dependencies where dependency.dependency_type == "required" {
                    if let id = dependency.version_id {
                        if let selected = (roots + resolved + queue).first(where: { $0.id == id }) { queue.append(selected) }
                        else { queue.append(try await client.get(ModrinthVersion.self, from: ModrinthEndpoints.version(id))) }
                    } else if let project = dependency.project_id {
                        if let selected = (roots + resolved + queue).first(where: { $0.project_id == project }) { queue.append(selected); continue }
                        if let record = installed.first(where: { $0.provider == "modrinth" && $0.projectID == project }),
                           let present = try? await version(record.versionID), present.project_id == project, present.game_versions.contains(instance.gameVersion), present.loaders.contains(instance.loader.modrinthLoader) {
                            queue.append(present); continue
                        }
                        let options = try await versions(project: project, game: instance.gameVersion, loader: instance.loader.modrinthLoader)
                        guard let match = options.first(where: { $0.version_type == "release" || $0.version_type == nil }) ?? options.first else { throw RuriError.message(Messages.CoreModrinthContentPlan.compatibleDependencyMissing(String(describing: project))) }
                        queue.append(match)
                    } else { throw RuriError.message(Messages.CoreModrinthContentPlan.missingDependencyDownloadID) }
                }
            }
        }
        for item in resolved {
            for dependency in item.dependencies where dependency.dependency_type == "incompatible" {
                let selectedConflict = resolved.contains { other in dependency.version_id.map { $0 == other.id } ?? (dependency.project_id == other.project_id) }
                let installedConflict = installed.contains { record in
                    record.provider == "modrinth" && record.enabled && !resolved.contains(where: { $0.project_id == record.projectID }) &&
                    (dependency.version_id.map { $0 == record.versionID } ?? (dependency.project_id == record.projectID))
                }
                if selectedConflict || installedConflict {
                    throw RuriError.message(Messages.CoreModrinthContentPlan.selectedContentIncompatible(item.name))
                }
            }
        }
        return try resolved.map { item in
            guard let file = item.primaryFile else { throw RuriError.message(Messages.CoreModrinthContentPlan.noDownloadableFile(item.name)) }
            guard file.hashes["sha1"] != nil || file.hashes["sha512"] != nil else { throw RuriError.message(Messages.CoreModrinthContentPlan.missingFileChecksum(file.filename)) }
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
            await progress(InstallProgress(Messages.CoreModrinthContentPlan.downloadingContent(item.file.filename), completed: result.count, total: plan.count))
            try await downloader.fetch(DownloadItem(url: item.file.url, destination: destination, sha1: item.record.sha1, sha512: item.record.sha512, size: item.record.size))
            result.append(ContentInstallation(record: item.record, source: destination))
        }
        return result
    }
}
