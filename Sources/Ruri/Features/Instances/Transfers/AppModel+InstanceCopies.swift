import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func copyInstance(_ preview: InstanceCopyPreview, completed: @escaping @MainActor @Sendable () -> Void) {
        guard !busy, !readOnly else { return }
        if state != persistedState { save() }
        guard !readOnly else { return }
        perform(Messages.AppAppModelInstanceCopies.copyInstance(preview.source.name)) { [self] activity in
            do {
                let result = try await InstanceCopier(paths: basePaths).copy(preview) { [weak self] value in Task { @MainActor in self?.progress(activity, value.progress) } }
                acceptState(try StateStore.load(basePaths))
                notice = result.warning ?? Messages.AppAppModelInstanceCopies.copyCreated(preview.copy.name).localized
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
        perform(Messages.AppAppModelInstanceCopies.recoverInstanceCopy(String(describing: pending.owner.copyName))) { [self] _ in
            let result = try await InstanceCopier(paths: basePaths).recover(sourceID: pending.owner.sourceID, transactionID: pending.owner.transactionID)
            acceptState(try StateStore.load(basePaths))
            notice = result.warning ?? (pending.committed ? Messages.AppAppModelInstanceCopies.copyCompleted.localized : Messages.AppAppModelInstanceCopies.copyKept.localized)
            noticeFileURL = result.preservedCopy
        }
    }
}
