import Foundation
import RuriCore

extension AppModel {
    func copyInstance(_ preview: InstanceCopyPreview, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform("复制 \(preview.source.name)") { [self] activity in
            do {
                let result = try await InstanceCopier(paths: basePaths).copy(preview) { [weak self] value in Task { @MainActor in self?.progress(activity, value.progress) } }
                acceptState(try StateStore.load(basePaths))
                notice = result.warning ?? "已创建“\(preview.copy.name)”，游戏文件独立保存，原实例保留。"
                noticeFileURL = result.preservedCopy; page = .library; completed()
            } catch let failure as RunDirectoryCopyFailure {
                notice = failure.localizedDescription; noticeFileURL = failure.preservedCopy; throw failure
            }
        }
    }
    func recoverInstanceCopy(_ pending: InstanceCopyRecovery) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform("恢复 \(pending.owner.copyName) 的实例复制") { [self] _ in
            let result = try await InstanceCopier(paths: basePaths).recover(sourceID: pending.owner.sourceID, transactionID: pending.owner.transactionID)
            acceptState(try StateStore.load(basePaths))
            notice = result.warning ?? (pending.committed ? "副本已完成，复制记录已清理。" : "未完成的副本已另行保留，原实例可继续使用。")
            noticeFileURL = result.preservedCopy
        }
    }
}
