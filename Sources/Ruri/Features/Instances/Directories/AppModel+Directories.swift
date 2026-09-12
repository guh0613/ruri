import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func selectDirectory(_ id: UUID) {
        guard !busy, !readOnly else { return }
        save(); guard !readOnly else { return }
        let base = basePaths
        perform(Messages.AppAppModelDirectories.switchGameDirectory) { [self] _ in
            let result = try await Task.detached(priority: .userInitiated) { try GameDirectoryStore.select(id, paths: base) }.value
            acceptState(result); page = .library
            await refreshDirectoryAvailability()
        }
    }

    func changeDirectory(_ work: (LauncherPaths) throws -> PersistentState) {
        guard !busy, !readOnly else { return }
        save()
        guard !readOnly else { return }
        do { acceptState(try work(paths)); Task { await refreshDirectoryAvailability() } }
        catch { self.error = error.localizedDescription }
    }
    func refreshDirectoryAvailability() async {
        let directories = state.gameDirectories ?? []
        let custom = state.instances.filter { $0.runDirectory == .custom }.compactMap { item in item.customRunDirectory.map { (item.id, $0) } }
        let errors = await Task.detached(priority: .utility) {
            var result: [UUID: String] = [:], customErrors: [UUID: String] = [:]
            for directory in directories {
                do { try directory.validateAvailability() } catch { result[directory.id] = error.localizedDescription }
            }
            for (id, location) in custom {
                do { try location.validateAvailability() } catch { customErrors[id] = error.localizedDescription }
            }
            return (result, customErrors)
        }.value
        directoryErrors = errors.0.filter { id, _ in state.gameDirectories?.contains(where: { $0.id == id }) == true }
        customDirectoryErrors = errors.1.filter { id, _ in
            guard let checked = custom.first(where: { $0.0 == id })?.1,
                  let instance = state.instances.first(where: { $0.id == id }), instance.runDirectory == .custom else { return false }
            return instance.customRunDirectory?.isSameLocation(as: checked) == true
        }
    }
    func relocateCustomDirectory(_ preview: CustomRunDirectoryRelocationPreview, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform(Messages.AppAppModelDirectories.relocateCustomDirectory) { [self] _ in
            _ = try await CustomRunDirectoryRelocation(paths: basePaths).apply(preview)
            acceptState(try StateStore.load(basePaths))
            await refreshDirectoryAvailability()
            notice = Messages.AppAppModelDirectories.relocatedInstances(Int64(preview.instances.count)).localized
            completed()
        }
    }
    func changeGameRunDirectory(_ preview: GameRunDirectoryChangePreview, copyFiles: Bool = false) {
        perform(Messages.AppAppModelDirectories.runDirectoryForInstance(String(describing: copyFiles ? Messages.AppAppModelDirectories.copyAndSwitch.localized : Messages.AppAppModelDirectories.switchDirectory.localized), preview.instanceName)) { [self] activity in
            let service = GameRunDirectoryChange(paths: paths)
            do {
                let result: RunDirectoryCopyResult?
                if copyFiles {
                    result = try await service.copyToEmpty(preview) { [weak self] value in Task { @MainActor in self?.progress(activity, value.progress) } }
                } else { _ = try await service.useExisting(preview); result = nil }
                acceptState(try StateStore.load(basePaths))
                notice = result?.warning ?? Messages.AppAppModelDirectories.directorySwitchCompleted(preview.instanceName, String(describing: copyFiles ? Messages.AppAppModelDirectories.copyAndSwitch.localized : Messages.AppAppModelDirectories.useTargetContents.localized)).localized
                noticeFileURL = result?.preservedCopy
            } catch let failure as RunDirectoryCopyFailure {
                notice = failure.localizedDescription; noticeFileURL = failure.preservedCopy
                throw failure
            }
        }
    }
    func recoverGameRunDirectory(_ pending: RunDirectoryCopyRecovery) {
        perform(Messages.AppAppModelDirectories.recoverDirectoryCopy(pending.owner.instanceName)) { [self] _ in
            let result = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: pending.owner.instanceID, transactionID: pending.owner.transactionID)
            acceptState(try StateStore.load(basePaths))
            notice = result.warning ?? (pending.committed ? Messages.AppAppModelDirectories.cleanedCopyRecord.localized : Messages.AppAppModelDirectories.directorySwitchRecovered.localized)
            noticeFileURL = result.preservedCopy
        }
    }
}
