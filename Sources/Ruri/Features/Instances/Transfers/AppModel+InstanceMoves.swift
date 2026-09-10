import Foundation
import RuriCore

extension AppModel {
    func moveInstance(_ preview: InstanceMovePreview, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform("移动 \(preview.source.name)") { [self] activity in
            do {
                let result = try await InstanceMover(paths: basePaths).move(preview) { [weak self] value in
                    Task { @MainActor in self?.progress(activity, value.progress) }
                }
                acceptState(try StateStore.load(basePaths)); page = .library
                notice = result.warning ?? "已移动“\(preview.moved.name)”，设置和运行历史已保留。"
                noticeFileURL = result.preservedFiles.first
                if !InstanceMoveGuard.hasPending(paths: basePaths, instanceID: preview.moved.id) { completed() }
            } catch let failure as InstanceMoveFailure {
                notice = failure.localizedDescription; noticeFileURL = failure.preservedFiles.first; throw failure
            }
        }
    }
    func recoverInstanceMove(_ pending: InstanceMoveRecovery, preservingSource: Bool, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform("恢复 \(pending.instance.name) 的移动") { [self] activity in
            let result = try await InstanceMover(paths: basePaths).recover(instanceID: pending.instance.id, transactionID: pending.id, preservingSource: preservingSource) { [weak self] value in
                Task { @MainActor in self?.progress(activity, value.progress) }
            }
            acceptState(try StateStore.load(basePaths)); page = .library
            notice = result.warning ?? "实例移动已完成，原文件与工作记录已清理。"
            noticeFileURL = result.preservedFiles.first; completed()
        }
    }
}
