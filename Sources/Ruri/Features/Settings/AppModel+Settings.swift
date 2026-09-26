import Foundation
import RuriCore

extension AppModel {
    @discardableResult func updateDefaultLaunchSettings(_ draft: LaunchSettingsValues, basedOn original: LaunchSettingsValues) -> Bool {
        guard !readOnly else { return false }
        do {
            acceptState(try ConfigurationService(paths: basePaths).saveDefaults(draft, basedOn: original))
        } catch { self.error = error.localizedDescription; return false }
        Task { await scanJava() }
        return !readOnly
    }
    func applyNetworkSettings() async {
        await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic)
        await downloader.configure(concurrency: state.settings.concurrentDownloads, cache: DownloadCache(paths: basePaths))
    }
}
