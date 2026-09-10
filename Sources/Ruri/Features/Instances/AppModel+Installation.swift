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
        perform("安装 \(instance.name)", instanceID: instance.id) { [self] id in
            let result = try await installer.install(instance, concurrency: state.settings.concurrentDownloads) { [weak self] progress in
                await self?.progress(id, progress)
            }
            try recordInstallation(result, requested: instance); notice = "\(result.name) 已准备就绪"
        }
    }
    func recordInstallation(_ result: GameInstance, requested: GameInstance) throws {
        save()
        guard !readOnly else { throw RuriError.message("设置写入已暂停，安装结果尚未登记。请重新载入后检查实例。") }
        let saved = try StateStore.update(basePaths) { latest in
            guard let index = latest.instances.firstIndex(where: { $0.id == result.id }) else { throw RuriError.message("实例已被移除，未重新登记。") }
            latest.instances[index] = try latest.instances[index].applyingInstallation(result, requested: requested)
        }
        acceptState(saved)
    }
    func repair(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id) else { return }
        perform("修复 \(instance.name)", instanceID: instance.id) { [self] id in
            try await installer.repair(instance, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
        }
    }
}
