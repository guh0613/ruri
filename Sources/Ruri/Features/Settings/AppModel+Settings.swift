import Foundation
import RuriCore

extension AppModel {
    @discardableResult func updateDefaultLaunchSettings(_ draft: LaunchSettingsValues, basedOn original: LaunchSettingsValues) -> Bool {
        guard !readOnly else { return false }
        let values = ConfigurationService.launchValues(draft)
        let previous = ConfigurationService.launchValues(original)
        let patch = Dictionary(uniqueKeysWithValues: LaunchSettingKey.allCases.compactMap { key in
            values[key.rawValue] == previous[key.rawValue] ? nil : (key.rawValue, values[key.rawValue])
        })
        do {
            _ = try ConfigurationService(paths: basePaths).apply(.init(set: patch), scope: "defaults")
            acceptState(try StateStore.load(basePaths))
        } catch { self.error = error.localizedDescription; return false }
        Task { await scanJava() }
        return !readOnly
    }
    func applyNetworkSettings() async {
        await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic)
        await downloader.configure(concurrency: state.settings.concurrentDownloads, cache: DownloadCache(paths: basePaths))
    }
}
