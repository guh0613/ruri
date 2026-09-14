import Foundation
import RuriLocalization

public enum CatalogFileAction: Sendable {
    case install, update, updateAndEnable, enable, keep
    public var title: String { switch self {
    case .install: Messages.Discovery.willInstall.localized
    case .update: Messages.Discovery.willUpdate.localized
    case .updateAndEnable: Messages.Discovery.willUpdateAndEnable.localized
    case .enable: Messages.Discovery.willEnable.localized
    case .keep: Messages.Discovery.alreadyInstalled.localized
    } }
}
public enum CatalogPlannedPayload: Sendable {
    case modrinth(PlannedModrinthFile), curseforge(PlannedCurseFile)
    public var record: ManagedContent { switch self { case .modrinth(let p): p.record; case .curseforge(let p): p.record } }
}
public struct CatalogPlannedItem: Identifiable, Sendable {
    public var id: String { payload.record.id }
    public let payload: CatalogPlannedPayload
    public let action: CatalogFileAction
    public let isRoot: Bool
    public let previousVersion: String?
    public let localFile: URL?
    public var record: ManagedContent { payload.record }
}
public struct CatalogInstallPlan: Sendable {
    public let instance: GameInstance
    public let items: [CatalogPlannedItem]
    public let untrackedFiles: Int
    public let baseline: [ManagedContent]
    public let missingProjects: Set<String>
    public var pending: [CatalogPlannedItem] { items.filter { $0.action != .keep } }
    public var downloadSize: Int64 { pending.filter { $0.action != .enable }.reduce(0) { $0 + $1.record.size } }
    public var manualFiles: [PlannedCurseFile] { pending.filter { $0.action != .enable }.compactMap { if case .curseforge(let p) = $0.payload, p.requiresManualDownload { p } else { nil } } }
}
public struct CatalogInstallationPlanner: Sendable {
    let modrinth: ModrinthService
    let curseForge: @Sendable () throws -> CurseForgeService
    public init(modrinth: ModrinthService = ModrinthService(), curseForge: @escaping @Sendable () throws -> CurseForgeService = { try CurseForgeService(apiKey: CurseForgeKeyStore.load()) }) {
        self.modrinth = modrinth; self.curseForge = curseForge
    }
    public func plan(project: CatalogProject, version: CatalogVersion, instance: GameInstance, paths: LauncherPaths, newInstance: Bool = false) async throws -> CatalogInstallPlan {
        switch (project, version) {
        case (.modrinth(let project), .modrinth(let version)) where project.id == version.project_id: break
        case (.curseforge(let project), .curseforge(let file)) where project.id == file.modId: break
        default: throw RuriError.message(Messages.Discovery.versionProjectMismatch)
        }
        guard version.supports(instance, type: project.type), let kind = ContentKind(rawValue: project.type) else { throw RuriError.message(Messages.Discovery.incompatibleTarget) }
        let installed: [ManagedContent]
        let local: [LocalContentFile]
        if newInstance { installed = []; local = [] }
        else {
            let manager = ContentManager(paths: paths, instanceID: instance.id)
            installed = try await manager.records()
            local = try await manager.scan(kind)
        }
        let files: [CatalogPlannedPayload]
        switch version {
        case .modrinth(let version): files = try await modrinth.plan(versions: [version], kind: kind, instance: instance, installed: installed).map(CatalogPlannedPayload.modrinth)
        case .curseforge(let file): files = try await curseForge().plan(file: file, instance: instance, paths: paths, installed: installed).files.map(CatalogPlannedPayload.curseforge)
        }
        let items = try files.map { payload in
            let record = payload.record
            let previous = installed.first { $0.id == record.id }
            let existingFile = local.first { $0.managed?.id == record.id }
            if let previous, let existingFile {
                let check = DownloadItem(url: nil, destination: existingFile.url, sha1: previous.sha1, sha512: previous.sha512, md5: previous.md5, size: previous.size)
                guard DownloadManager.valid(existingFile.url, item: check) else { throw RuriError.message(Messages.CoreContentManager.externallyModifiedContent(previous.filename)) }
            }
            let valid: Bool
            if let existingFile, previous?.versionID == record.versionID {
                valid = DownloadManager.valid(existingFile.url, item: DownloadItem(url: nil, destination: existingFile.url, sha1: record.sha1, sha512: record.sha512, md5: record.md5, size: record.size))
            } else { valid = false }
            let action: CatalogFileAction = valid ? (previous?.enabled == true ? .keep : .enable) : previous == nil ? .install : previous?.enabled == false ? .updateAndEnable : .update
            return CatalogPlannedItem(payload: payload, action: action, isRoot: record.projectID == project.projectID, previousVersion: previous?.versionName, localFile: existingFile?.url)
        }
        return CatalogInstallPlan(instance: instance, items: items, untrackedFiles: local.filter { $0.managed == nil }.count, baseline: installed, missingProjects: Set(installed.filter { record in !local.contains { $0.managed?.id == record.id } }.map(\.id)))
    }
    public func install(_ plan: CatalogInstallPlan, paths: LauncherPaths, downloader: DownloadManager, manualFiles: [Int: URL] = [:], progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let mr: [PlannedModrinthFile] = plan.pending.filter { $0.action != .enable }.compactMap { if case .modrinth(let p) = $0.payload { p } else { nil } }
        let cf: [PlannedCurseFile] = plan.pending.filter { $0.action != .enable }.compactMap { if case .curseforge(let p) = $0.payload { p } else { nil } }
        let manager = ContentManager(paths: paths, instanceID: plan.instance.id)
        guard try await manager.records().sorted(by: { $0.id < $1.id }) == plan.baseline.sorted(by: { $0.id < $1.id }) else { throw RuriError.message(Messages.Discovery.contentChanged) }
        var files = try await modrinth.materialize(mr, paths: paths, downloader: downloader, progress: progress)
        if !cf.isEmpty { files += try await CurseForgeService(apiKey: "").materialize(cf, paths: paths, downloader: downloader, manualFiles: manualFiles, progress: progress) }
        // ContentManager removes replaced paths before copying incoming sources.
        // Stage existing disabled files outside the instance before reenabling.
        let stage = paths.cache.appendingPathComponent("catalog-enable-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: stage) }
        for item in plan.pending where item.action == .enable {
            guard let local = item.localFile else { throw RuriError.message(Messages.Discovery.contentChanged) }
            try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
            let copy = stage.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: local, to: copy)
            files.append(ContentInstallation(record: item.record, source: copy))
        }
        try Task.checkCancellation()
        for item in plan.items where item.action == .keep {
            guard let file = item.localFile, DownloadManager.valid(file, item: DownloadItem(url: nil, destination: file, sha1: item.record.sha1, sha512: item.record.sha512, md5: item.record.md5, size: item.record.size)) else { throw RuriError.message(Messages.Discovery.contentChanged) }
        }
        if !files.isEmpty {
            await progress(InstallProgress(Messages.Discovery.applyingInstall))
            try await manager.install(files, expecting: plan.baseline, enabling: Set(plan.pending.filter { $0.action == .enable || $0.action == .updateAndEnable }.map(\.id)), allowingMissing: plan.missingProjects)
        }
    }
}
