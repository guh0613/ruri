import RuriLocalization
import SwiftUI
import RuriCore

enum ContentStatusFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled
    var id: String { rawValue }
    var title: String { switch self { case .all: Messages.AppContentRemovalView.titleText1.localized; case .enabled: Messages.AppContentRemovalView.titleText2.localized; case .disabled: Messages.AppContentRemovalView.titleText3.localized } }
}
struct ContentRemovalSelection: Identifiable {
    let id = UUID()
    let files: [LocalContentFile]
}
struct ContentRemovalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let files: [LocalContentFile]
    let instanceID: UUID
    let remove: @MainActor @Sendable () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(Messages.AppContentRemovalView.bodyText1(Int64(files.count)).localized).font(.title2.bold())
            Text(Messages.AppContentRemovalView.bodyText2.localized).font(.callout).foregroundStyle(.secondary)
            List(files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.title).font(.headline)
                    Text(file.url.lastPathComponent).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }.listStyle(.bordered)
            HStack {
                Text(LocalizedFormat.bytes(files.reduce(0) { $0 + $1.size })).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppContentRemovalView.bodyText3.localized, role: .destructive) { remove(); dismiss() }.disabled(model.busy || model.isInstanceInUse(instanceID))
            }
        }.padding(24).frame(width: 500, height: 430)
    }
}
