import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct RepositoryImportRecoveryView: View {
    @Environment(AppModel.self) private var model
    let directoryID: UUID
    @State private var pending: [RepositoryImportRecovery] = []
    @State private var issue: String?
    private var refreshKey: String { "\(directoryID):\(model.busy):\(model.state.revision?.uuidString ?? "")" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pending) { item in
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(item.copySource != nil ? (item.registered ? Messages.AppRepositoryImportRecoveryView.bodyText1.localized : Messages.AppRepositoryImportRecoveryView.bodyText2.localized) : (item.registered ? Messages.AppRepositoryImportRecoveryView.bodyText3.localized : Messages.AppRepositoryImportRecoveryView.bodyText4.localized))：\(item.name)", systemImage: "shippingbox.and.arrow.backward").font(.headline)
                        Text(item.canFinish ? Messages.AppRepositoryImportRecoveryView.bodyText5.localized : Messages.AppRepositoryImportRecoveryView.bodyText6.localized)
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            if item.canFinish { Button(item.copySource == nil ? Messages.AppRepositoryImportRecoveryView.bodyText7.localized : Messages.AppRepositoryImportRecoveryView.bodyText8.localized) { recover(item, finish: true) }.buttonStyle(.borderedProminent).disabled(model.busy) }
                            if !item.registered { Button(Messages.AppRepositoryImportRecoveryView.bodyText9.localized) { recover(item, finish: false) }.disabled(model.busy) }
                            Button(Messages.AppRepositoryImportRecoveryView.bodyText10.localized) { NSWorkspace.shared.open(item.workspace) }
                        }
                    }
                }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
        .task(id: refreshKey) {
            guard !model.busy else { return }
            let paths = model.basePaths
            do {
                let result = try await Task.detached(priority: .utility) { try RepositoryImportStore.pending(directoryID: directoryID, paths: paths) }.value
                try Task.checkCancellation(); pending = result; issue = nil
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
        }
    }
    private func recover(_ item: RepositoryImportRecovery, finish: Bool) {
        let base = model.basePaths
        model.perform(finish ? Messages.AppRepositoryImportRecoveryView.baseText1.localized : Messages.AppRepositoryImportRecoveryView.baseText2.localized) { _ in
            let kept = try await Task.detached(priority: .userInitiated) {
                try RepositoryImportStore.recover(item.id, directoryID: directoryID, finish: finish, paths: base)
            }.value
            model.acceptState(try StateStore.load(base))
            model.notice = finish ? Messages.AppRepositoryImportRecoveryView.keptText1(String(describing: item.name)).localized : Messages.AppRepositoryImportRecoveryView.keptText2.localized
            model.noticeFileURL = kept
            pending.removeAll { $0.id == item.id }
        }
    }
}
