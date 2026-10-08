import RuriLocalization
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
    func cacheSummary() async -> CacheMaintenance.Summary {
        let maintenance = CacheMaintenance(paths: basePaths)
        return await Task.detached(priority: .utility) { maintenance.survey() }.value
    }
    /// Returns false when another operation keeps the cleanup from starting.
    @discardableResult func cleanCache(finished: @escaping @MainActor (CacheMaintenance.Summary) -> Void = { _ in }) -> Bool {
        guard !busy, !readOnly else { return false }
        perform(Messages.AppPreferencesView.cleaningCache) { [self] _ in
            let maintenance = CacheMaintenance(paths: basePaths)
            let freed = await Task.detached(priority: .utility) { maintenance.clean() }.value
            report(Messages.AppPreferencesView.cacheCleaned(LocalizedFormat.bytes(freed.bytes)), level: .success)
            finished(freed)
        }
        return true
    }
    func applyNetworkSettings() async {
        await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic)
        await downloader.configure(concurrency: state.settings.concurrentDownloads, cache: DownloadCache(paths: basePaths))
    }
}
