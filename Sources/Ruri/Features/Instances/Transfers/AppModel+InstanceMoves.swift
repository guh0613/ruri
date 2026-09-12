import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func moveInstance(_ preview: InstanceMovePreview, failed: @escaping @MainActor @Sendable (String) -> Void, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform(Messages.AppAppModelInstanceMoves.moveInstance(preview.source.name), presentErrors: false) { [self] activity in
            do {
                let result = try await InstanceMover(paths: basePaths).move(preview) { [weak self] value in
                    Task { @MainActor in self?.progress(activity, value.progress) }
                }
                acceptState(try StateStore.load(basePaths)); page = .library
                notice = result.warning ?? Messages.AppAppModelInstanceMoves.instanceMoved(preview.moved.name).localized
                noticeFileURL = result.preservedFiles.first
                if InstanceMoveGuard.hasPending(paths: basePaths, instanceID: preview.moved.id) {
                    throw InstanceMoveFailure(message: result.warning ?? Messages.AppAppModelInstanceMoves.moveNeedsRecovery.localized, preservedFiles: result.preservedFiles, cancelled: Task.isCancelled)
                }
                completed()
            } catch {
                if let failure = error as? InstanceMoveFailure { notice = failure.localizedDescription; noticeFileURL = failure.preservedFiles.first }
                failed(error.localizedDescription); throw error
            }
        }
    }
    func recoverInstanceMove(_ pending: InstanceMoveRecovery, preservingSource: Bool, failed: @escaping @MainActor @Sendable (String) -> Void, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform(Messages.AppAppModelInstanceMoves.recoverInstanceMove(pending.instance.name), presentErrors: false) { [self] activity in
            do {
                let result = try await InstanceMover(paths: basePaths).recover(instanceID: pending.instance.id, transactionID: pending.id, preservingSource: preservingSource) { [weak self] value in
                    Task { @MainActor in self?.progress(activity, value.progress) }
                }
                acceptState(try StateStore.load(basePaths)); page = .library
                notice = result.warning ?? Messages.AppAppModelInstanceMoves.instanceMoveCompleted.localized
                noticeFileURL = result.preservedFiles.first; completed()
            } catch {
                failed(error.localizedDescription); throw error
            }
        }
    }
}
