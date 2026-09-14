import AppKit
import Foundation
import RuriCore
import RuriLocalization

extension AppModel {
    func installCatalog(_ plan: CatalogInstallPlan, newInstance: Bool, name: String, manualFiles: [Int: URL]) {
        guard !busy, !readOnly, newInstance || !isInstanceInUse(plan.instance.id) else { return }
        let instance: GameInstance
        do {
            if newInstance {
                var draft = plan.instance
                let chosenName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !chosenName.isEmpty { draft.name = chosenName }
                instance = try MinecraftFolderStore.preparingNewInstance(draft, paths: paths)
                state.instances.append(instance); select(instance)
                guard !readOnly else { return }
            } else {
                guard let current = state.instances.first(where: { $0.id == plan.instance.id }), current.installed,
                      current.gameVersion == plan.instance.gameVersion, current.loader == plan.instance.loader,
                      current.loaderVersion == plan.instance.loaderVersion else { throw RuriError.message(Messages.Discovery.instanceChanged) }
                instance = current
            }
        } catch { self.error = error.localizedDescription; return }
        perform(Messages.Discovery.installingInto(instance.name), instanceID: instance.id) { [self] id in
            if newInstance {
                let result = try await installer.install(instance, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                try recordInstallation(result, requested: instance)
            }
            let current = try StateStore.load(paths).instances.first { $0.id == instance.id }
            guard current?.gameVersion == plan.instance.gameVersion, current?.loader == plan.instance.loader,
                  current?.loaderVersion == plan.instance.loaderVersion else { throw RuriError.message(Messages.Discovery.instanceChanged) }
            try await CatalogInstallationPlanner().install(plan, paths: paths, downloader: downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
            report(Messages.Discovery.installComplete(instance.name))
        }
    }
    @discardableResult func saveCatalogFile(project: CatalogProject, version: CatalogVersion, manualFiles: [Int: URL]) -> Bool {
        guard !busy, !readOnly else { return false }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: version.filename).lastPathComponent
        panel.canCreateDirectories = true
        panel.title = Messages.Discovery.saveFile.localized
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        perform(Messages.Discovery.downloadingFile(version.filename)) { [self] id in
            let scoped = destination.startAccessingSecurityScopedResource()
            defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
            progress(id, InstallProgress(Messages.Discovery.downloadingFile(version.filename)))
            switch (project, version) {
            case (.modrinth, .modrinth(let version)):
                guard let file = version.primaryFile else { throw RuriError.message(Messages.CoreModrinthContentPlan.noDownloadableFile(version.name)) }
                guard file.hashes["sha1"] != nil || file.hashes["sha512"] != nil else { throw RuriError.message(Messages.CoreModrinthContentPlan.missingFileChecksum(file.filename)) }
                try await downloader.fetch(DownloadItem(url: file.url, destination: destination, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
            case (.curseforge(let project), .curseforge(let file)):
                if let manual = manualFiles[file.id] {
                    let check = try file.downloadItem(to: manual, permittedURL: nil)
                    guard DownloadManager.valid(manual, item: check) else { throw RuriError.message(Messages.CoreCurseForge.fileMismatch(file.displayName)) }
                    let temporary = destination.deletingLastPathComponent().appendingPathComponent(".ruri-export-" + UUID().uuidString)
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: manual, to: temporary)
                    try Task.checkCancellation()
                    guard rename(temporary.path, destination.path) == 0 else { throw RuriError.message(Messages.Discovery.saveFailed) }
                } else {
                    guard project.allowModDistribution != false, let url = file.downloadURL else { throw RuriError.message(Messages.CoreCurseForge.manualDownloadRequired(file.fileName)) }
                    try await downloader.fetch(file.downloadItem(to: destination, permittedURL: url))
                }
            default: throw RuriError.message(Messages.Discovery.incompatibleTarget)
            }
            report(Messages.Discovery.savedFile(destination.lastPathComponent))
        }
        return true
    }
}
