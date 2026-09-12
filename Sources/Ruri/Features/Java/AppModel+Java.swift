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
        panel.message = path == nil ? Messages.AppAppModelJava.panelText1.localized : Messages.AppAppModelJava.panelText2.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save()
        perform(path == nil ? Messages.AppAppModelJava.urlText1.localized : Messages.AppAppModelJava.urlText2.localized) { [self] _ in
            let saved = try await JavaRuntimeStore.add(url, replacing: path, paths: paths)
            acceptState(saved); await scanJava(); notice = Messages.AppAppModelJava.savedText1.localized
        }
    }
    func forgetJava(_ path: String) {
        do { save(); acceptState(try JavaRuntimeStore.forget(path, paths: paths)); Task { await scanJava() } }
        catch { self.error = error.localizedDescription }
    }
    func defaultJava(_ path: String) {
        do { save(); acceptState(try JavaRuntimeStore.useByDefault(path, paths: paths)); notice = Messages.AppAppModelJava.defaultJavaText1.localized }
        catch { self.error = error.localizedDescription }
    }
    func installJava(_ runtime: RemoteJava, repairing: Bool = false) {
        perform("\(repairing ? Messages.AppAppModelJava.installJavaText1.localized : Messages.AppAppModelJava.installJavaText2.localized) \(runtime.label)") { [self] id in
            do {
                _ = try await JavaInstaller(paths: paths).install(runtime, downloader: downloader, repairing: repairing) { [weak self] p in await self?.progress(id, p) }
                await scanJava(); notice = repairing ? Messages.AppAppModelJava.installJavaText3.localized : Messages.AppAppModelJava.installJavaText4.localized
            } catch { await scanJava(); throw error }
        }
    }
    func removeJava(_ id: String, resetReferences: Bool, partial: Bool) {
        save()
        perform(partial ? Messages.AppAppModelJava.removeJavaText1.localized : Messages.AppAppModelJava.removeJavaText2.localized) { [self] _ in
            let paths = paths
            let result = try await Task.detached(priority: .userInitiated) { try JavaRuntimeStore.trash(id, paths: paths, resetReferences: resetReferences, partial: partial) }.value
            acceptState(result.state); await scanJava(); notice = Messages.AppAppModelJava.resultText1.localized; noticeFileURL = result.trashedURL
        }
    }
}
