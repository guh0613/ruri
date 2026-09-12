import RuriLocalization
import Foundation

public struct ContentBatchUpdatePlan: Identifiable, Sendable {
    public let id = UUID()
    public let instance: GameInstance
    public let selectedIDs: Set<String>
    public let baseline: [ManagedContent]
    public let modrinth: [PlannedModrinthFile]
    public let curseforge: [PlannedCurseFile]
    public var records: [ManagedContent] { modrinth.map(\.record) + curseforge.map(\.record) }
    public var downloadSize: Int64 { records.reduce(0) { $0 + $1.size } }
}

public actor ContentBatchUpdater {
    let modrinth: ModrinthService
    let curseforge: CurseForgeService
    public init(modrinth: ModrinthService = ModrinthService(), curseforge: CurseForgeService) {
        self.modrinth = modrinth; self.curseforge = curseforge
    }

    public func prepare(modrinth updates: [ContentUpdate], curseforge curseUpdates: [CurseForgeUpdate], instance: GameInstance, paths: LauncherPaths) async throws -> ContentBatchUpdatePlan {
        let selected = updates.map(\.installed) + curseUpdates.map(\.installed)
        guard !selected.isEmpty, Set(selected.map(\.id)).count == selected.count else { throw RuriError.message(Messages.CoreContentBatchUpdater.selectedText1) }
        let manager = ContentManager(paths: paths, instanceID: instance.id), baseline = try await manager.records()
        for record in selected {
            guard baseline.contains(record), FileManager.default.fileExists(atPath: paths.game(instance.id).appendingPathComponent(record.relativePath).path) else { throw RuriError.message(Messages.CoreContentBatchUpdater.managerText1(String(describing: record.title))) }
        }
        guard updates.allSatisfy({ $0.installed.provider == "modrinth" && $0.installed.projectID == $0.available.project_id }),
              curseUpdates.allSatisfy({ $0.installed.provider == "curseforge" && $0.installed.projectID == String($0.available.modId) }) else { throw RuriError.message(Messages.CoreContentBatchUpdater.managerText2) }
        var modFiles: [PlannedModrinthFile] = []
        for kind in ContentKind.allCases {
            let roots = updates.filter { $0.installed.kind == kind }.map(\.available)
            if !roots.isEmpty { modFiles += try await modrinth.plan(versions: roots, kind: kind, instance: instance) }
        }
        let curseFiles = curseUpdates.isEmpty ? [] : try await curseforge.plan(files: curseUpdates.map(\.available), instance: instance, paths: paths).files
        let selectedIDs = Set(selected.map(\.id))
        func needsInstall(_ record: ManagedContent) -> Bool {
            guard !selectedIDs.contains(record.id), let old = baseline.first(where: { $0.id == record.id }), old.versionID == record.versionID, old.filename == record.filename else { return true }
            let file = paths.game(instance.id).appendingPathComponent(old.relativePath)
            return !DownloadManager.valid(file, item: DownloadItem(url: nil, destination: file, sha1: record.sha1, sha512: record.sha512, md5: record.md5, size: record.size))
        }
        return ContentBatchUpdatePlan(instance: instance, selectedIDs: selectedIDs, baseline: baseline,
                                      modrinth: modFiles.filter { needsInstall($0.record) }, curseforge: curseFiles.filter { needsInstall($0.record) })
    }

    public func install(_ plan: ContentBatchUpdatePlan, paths: LauncherPaths, downloader: DownloadManager, manualFiles: [Int: URL] = [:],
                        progress: @Sendable @escaping (InstallProgress) async -> Void) async throws {
        let state = try StateStore.load(paths)
        guard let current = state.instances.first(where: { $0.id == plan.instance.id }),
              current.gameVersion == plan.instance.gameVersion, current.loader == plan.instance.loader, current.loaderVersion == plan.instance.loaderVersion else {
            throw RuriError.message(Messages.CoreContentBatchUpdater.currentText1)
        }
        try paths.validateBinding(current)
        _ = try current.applyingInstallation(plan.instance, requested: plan.instance)
        // Resolve and verify every file before the existing content journal
        // commits either provider's updates.
        let curseFiles = try await curseforge.materialize(plan.curseforge, paths: paths, downloader: downloader, manualFiles: manualFiles, progress: progress)
        let modFiles = try await modrinth.materialize(plan.modrinth, paths: paths, downloader: downloader, progress: progress)
        try Task.checkCancellation()
        await progress(InstallProgress(Messages.CoreContentBatchUpdater.modFilesText1(Int64(plan.selectedIDs.count))))
        try await ContentManager(paths: paths, instanceID: current.id).install(modFiles + curseFiles, expecting: plan.baseline)
    }
}
