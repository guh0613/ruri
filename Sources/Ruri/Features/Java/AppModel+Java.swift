import RuriLocalization
import Foundation
import AppKit
import RuriCore

extension AppModel {
    func scanJava() async {
        guard !scanningJava else { javaScanAgain = true; return }
        scanningJava = true
        repeat {
            javaScanAgain = false
            let extra = state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path } + [state.settings.defaultLaunchSettings.java.path].compactMap { $0 }
            javaEntries = await JavaDiscovery.inventory(paths: paths, extra: extra)
            runtimes = javaEntries.compactMap(\.runtime)
        } while javaScanAgain
        scanningJava = false
    }
    func chooseJava(replacing path: String? = nil) {
        let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = path == nil ? Messages.AppAppModelJava.javaPathPurpose.localized : Messages.AppAppModelJava.javaPathReplacementDetails.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save()
        perform(path == nil ? Messages.AppAppModelJava.addLocalJava.localized : Messages.AppAppModelJava.chooseJavaAgain.localized) { [self] _ in
            let saved = try await JavaRuntimeStore.add(url, replacing: path, paths: paths)
            acceptState(saved); await scanJava(); report(Messages.AppAppModelJava.javaAdded)
        }
    }
    func forgetJava(_ path: String) {
        do { save(); acceptState(try JavaRuntimeStore.forget(path, paths: paths)); Task { await scanJava() } }
        catch { self.error = error.localizedDescription }
    }
    func defaultJava(_ path: String) {
        do { save(); acceptState(try JavaRuntimeStore.useByDefault(path, paths: paths)); report(Messages.AppAppModelJava.defaultJavaUpdated) }
        catch { self.error = error.localizedDescription }
    }
    func installJava(_ runtime: RemoteJava, repairing: Bool = false) {
        perform("\(repairing ? Messages.AppAppModelJava.repair.localized : Messages.AppAppModelJava.install.localized) \(runtime.label)") { [self] id in
            do {
                _ = try await JavaInstaller(paths: paths).install(runtime, downloader: downloader, repairing: repairing) { [weak self] p in await self?.progress(id, p) }
                await scanJava(); report(repairing ? Messages.AppAppModelJava.javaRepaired.localized : Messages.AppAppModelJava.javaInstalled.localized)
            } catch { await scanJava(); throw error }
        }
    }
    func removeJava(_ id: String, resetReferences: Bool, partial: Bool) {
        save()
        perform(partial ? Messages.AppAppModelJava.cleanIncompleteJavaDownload.localized : Messages.AppAppModelJava.removeJava.localized) { [self] _ in
            let paths = paths
            let result = try await Task.detached(priority: .userInitiated) { try JavaRuntimeStore.trash(id, paths: paths, resetReferences: resetReferences, partial: partial) }.value
            acceptState(result.state); await scanJava(); report(Messages.AppAppModelJava.javaMovedToTrash, fileURL: result.trashedURL)
        }
    }
}
