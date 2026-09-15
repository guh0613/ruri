import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

extension AppModel {
    func installCurseForge(_ plan: CurseForgeContentPlan, manualFiles: [Int: URL]) {
        guard !isInstanceInUse(plan.instance.id) else { return }
        perform(Messages.AppAppModelCurseForge.installPack(plan.title), instanceID: plan.instance.id) { [self] id in
            try await CurseForgeService(apiKey: "").install(plan, paths: paths, downloader: installer.downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
            report(Messages.AppAppModelCurseForge.packInstalled(plan.title))
        }
    }
    func readCurseForgePack(_ project: CurseForgeProject, file: CurseForgeFile, manual: URL?) {
        perform(Messages.AppAppModelCurseForge.readPack(project.name)) { [self] id in
            let archive: URL
            if let manual { archive = manual }
            else {
                guard project.allowModDistribution != false, let url = file.downloadURL else { throw RuriError.message(Messages.AppAppModelCurseForge.downloadRequired) }
                archive = try LauncherPaths.safePath("curseforge/\(file.id)/\(file.fileName)", within: paths.cache)
                try await installer.downloader.fetch(file.downloadItem(to: archive, permittedURL: url))
            }
            guard DownloadManager.valid(archive, item: try file.downloadItem(to: archive, permittedURL: nil)) else { throw RuriError.message(Messages.AppAppModelCurseForge.packValidationFailed) }
            let prepared = try await InstanceTransfer(paths: paths).prepare(archive, origin: ModpackOrigin(provider: .curseforge, projectID: String(project.id), versionID: String(file.id))) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
            importingInstance = await InstanceIconImage.download(project.logo?.thumbnailUrl).map(prepared.usingIcon) ?? prepared
        }
    }
}
