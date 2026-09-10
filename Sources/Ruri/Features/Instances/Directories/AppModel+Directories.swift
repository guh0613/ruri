import Foundation
import RuriCore

extension AppModel {
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
        perform("重新定位自定义游戏目录") { [self] _ in
            _ = try await CustomRunDirectoryRelocation(paths: basePaths).apply(preview)
            acceptState(try StateStore.load(basePaths))
            await refreshDirectoryAvailability()
            notice = "已更新 \(preview.instances.count) 个实例的目录位置，游戏文件保留在所选文件夹。"
            completed()
        }
    }
    func changeGameRunDirectory(_ preview: GameRunDirectoryChangePreview, copyFiles: Bool = false) {
        perform("\(copyFiles ? "复制并切换" : "切换") \(preview.instanceName) 的运行目录") { [self] activity in
            let service = GameRunDirectoryChange(paths: paths)
            do {
                let result: RunDirectoryCopyResult?
                if copyFiles {
                    result = try await service.copyToEmpty(preview) { [weak self] value in Task { @MainActor in self?.progress(activity, value.progress) } }
                } else { _ = try await service.useExisting(preview); result = nil }
                acceptState(try StateStore.load(basePaths))
                notice = result?.warning ?? "\(preview.instanceName) 已\(copyFiles ? "复制并切换" : "使用目标内容")；原目录及备份已保留。"
                noticeFileURL = result?.preservedCopy
            } catch let failure as RunDirectoryCopyFailure {
                notice = failure.localizedDescription; noticeFileURL = failure.preservedCopy
                throw failure
            }
        }
    }
    func recoverGameRunDirectory(_ pending: RunDirectoryCopyRecovery) {
        perform("恢复 \(pending.owner.instanceName) 的目录复制") { [self] _ in
            let result = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: pending.owner.instanceID, transactionID: pending.owner.transactionID)
            acceptState(try StateStore.load(basePaths))
            notice = result.warning ?? (pending.committed ? "已清理完成的复制记录，目标内容保留。" : "已恢复到切换前的状态，复制工作区另行保留。")
            noticeFileURL = result.preservedCopy
        }
    }
}
