import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func refreshCatalog() async {
        guard !catalogLoading else { return }
        catalogLoading = true; catalogError = nil
        defer { catalogLoading = false }
        do { catalog = try await installer.catalog() }
        catch {
            catalogError = error.localizedDescription
            if !Task.isCancelled { report(Messages.LauncherLog.catalogFailed(error.localizedDescription), level: .warning) }
        }
    }
    func install(name: String, version: String, loader: LoaderKind, loaderVersion: String?) {
        install(name: name, version: version, selections: loader == .vanilla ? [] : [.init(loader: loader, version: loaderVersion ?? "")])
    }
    func install(name: String, version: String, selections: [LoaderSelection]) {
        guard !busy, !readOnly else { return }
        if let issue = LoaderCompatibility.combinationIssue(selections.map(\.loader), game: version) { error = issue; return }
        let instance: GameInstance
        do {
            save(); guard !readOnly else { return }
            instance = try InstanceService(paths: paths).create(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Minecraft \(version)" : name,
                                                               game: version, selections: selections, directoryID: paths.newInstanceDirectoryID)
            acceptState(try StateStore.load(basePaths))
        } catch { self.error = error.localizedDescription; return }
        select(instance); showCreate = false; page = .activity
        install(instance)
    }
    func install(_ instance: GameInstance) {
        guard !busy, !readOnly else { return }
        perform(Messages.AppAppModelInstallation.installInstance(instance.name)) { [self] id in
            let result = try await InstanceService(paths: paths).install(instance.id, downloader: installer.downloader) { [weak self] progress in
                await self?.progress(id, progress)
            }
            acceptState(try StateStore.load(basePaths)); report(Messages.AppAppModelInstallation.installationResult(result.name))
        }
    }
    func recordInstallation(_ result: GameInstance, requested: GameInstance) throws {
        save()
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelInstallation.installationWritePaused) }
        let saved = try StateStore.update(basePaths) { latest in
            guard let index = latest.instances.firstIndex(where: { $0.id == result.id }) else { throw RuriError.message(Messages.AppAppModelInstallation.instanceRemoved) }
            latest.instances[index] = try latest.instances[index].applyingInstallation(result, requested: requested)
        }
        acceptState(saved)
    }
    func repair(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id) else { return }
        perform(Messages.AppAppModelInstallation.repairInstance(instance.name)) { [self] id in
            _ = try await InstanceService(paths: paths).install(instance.id, repair: true, downloader: installer.downloader) { [weak self] p in await self?.progress(id, p) }
        }
    }
    func changeComponents(_ instance: GameInstance, selections: [LoaderSelection]) {
        guard !busy, !readOnly, !isInstanceInUse(instance.id) else { return }
        save()
        perform(Messages.AppAppModelInstallation.changeLoader(instance.name)) { [self] id in
            let service = await InstanceComponents(paths: paths, downloader: installer.downloader)
            let saved = try await service.change(instance, selections: selections, concurrency: state.settings.concurrentDownloads) { [weak self] p in
                await self?.progress(id, p)
            }
            acceptState(saved); report(Messages.AppAppModelInstallation.loaderConfigurationSaved(instance.name, saved.instances.first(where: { $0.id == instance.id })?.loaderSummary ?? ""))
        }
    }
    func restoreComponents(_ instance: GameInstance) {
        guard !busy, !readOnly, !isInstanceInUse(instance.id) else { return }
        save()
        perform(Messages.AppAppModelInstallation.restoreLoaderConfiguration(instance.name)) { [self] _ in
            let saved = try await InstanceComponents(paths: paths).restore(instance)
            acceptState(saved); report(Messages.AppAppModelInstallation.loaderConfigurationRestored)
        }
    }
}
