import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func refreshCatalog() async {
        guard !catalogLoading else { return }
        catalogLoading = true; catalogError = nil
        defer { catalogLoading = false }
        do { catalog = try await installer.catalog() } catch { catalogError = error.localizedDescription }
    }
    func install(name: String, version: String, loader: LoaderKind, loaderVersion: String?) {
        guard !busy, !readOnly else { return }
        var instance = GameInstance(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Minecraft \(version)" : name, gameVersion: version, loader: loader, loaderVersion: loaderVersion)
        instance.launchOverrides = .init()
        instance.directoryID = paths.newInstanceDirectoryID
        instance.runDirectory = (state.settings.isolationPolicy ?? .always).directory(loader: loader)
        do { instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: paths) }
        catch { self.error = error.localizedDescription; return }
        state.instances.append(instance); select(instance); showCreate = false; page = .downloads
        install(instance)
    }
    func install(_ instance: GameInstance) {
        guard !busy, !readOnly else { return }
        perform(Messages.AppAppModelInstallation.installText1(String(describing: instance.name)), instanceID: instance.id) { [self] id in
            let result = try await installer.install(instance, concurrency: state.settings.concurrentDownloads) { [weak self] progress in
                await self?.progress(id, progress)
            }
            try recordInstallation(result, requested: instance); notice = Messages.AppAppModelInstallation.resultText1(String(describing: result.name)).localized
        }
    }
    func recordInstallation(_ result: GameInstance, requested: GameInstance) throws {
        save()
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelInstallation.recordInstallationText1) }
        let saved = try StateStore.update(basePaths) { latest in
            guard let index = latest.instances.firstIndex(where: { $0.id == result.id }) else { throw RuriError.message(Messages.AppAppModelInstallation.indexText1) }
            latest.instances[index] = try latest.instances[index].applyingInstallation(result, requested: requested)
        }
        acceptState(saved)
    }
    func repair(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id) else { return }
        perform(Messages.AppAppModelInstallation.repairText1(String(describing: instance.name)), instanceID: instance.id) { [self] id in
            try await installer.repair(instance, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
        }
    }
    func changeComponents(_ instance: GameInstance, loader: LoaderKind, version: String?) {
        guard !busy, !readOnly, !isInstanceInUse(instance.id) else { return }
        save()
        perform(Messages.AppAppModelInstallation.changeComponentsText1(String(describing: instance.name))) { [self] id in
            let service = await InstanceComponents(paths: paths, downloader: installer.downloader)
            let saved = try await service.change(instance, to: loader, version: version, concurrency: state.settings.concurrentDownloads) { [weak self] p in
                await self?.progress(id, p)
            }
            acceptState(saved); notice = Messages.AppAppModelInstallation.savedText1(String(describing: instance.name), String(describing: loader.title)).localized
        }
    }
    func restoreComponents(_ instance: GameInstance) {
        guard !busy, !readOnly, !isInstanceInUse(instance.id) else { return }
        save()
        perform(Messages.AppAppModelInstallation.restoreComponentsText1(String(describing: instance.name))) { [self] _ in
            let saved = try await InstanceComponents(paths: paths).restore(instance)
            acceptState(saved); notice = Messages.AppAppModelInstallation.savedText2.localized
        }
    }
}
