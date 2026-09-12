import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CustomRunDirectoryRelocationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instanceID: UUID
    @State private var selected: URL?
    @State private var preview: CustomRunDirectoryRelocationPreview?
    @State private var issue: String?
    @State private var checking = false
    @State private var refresh = UUID()
    private var original: CustomRunDirectory? { model.state.instances.first(where: { $0.id == instanceID })?.customRunDirectory }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: Messages.AppCustomRunDirectoryRelocationView.recoverDirectory.localized, subtitle: Messages.AppCustomRunDirectoryRelocationView.relocationHelp.localized)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(Messages.AppCustomRunDirectoryRelocationView.relocationInstructions.localized).font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Messages.AppCustomRunDirectoryRelocationView.originalLocation.localized).font(.headline)
                        Text(original?.url.path ?? Messages.AppCustomRunDirectoryRelocationView.unregisteredDirectory.localized).font(.caption).textSelection(.enabled)
                    }
                    HStack {
                        Text(selected?.path ?? Messages.AppCustomRunDirectoryRelocationView.newLocationNotSelected.localized).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button(Messages.AppCustomRunDirectoryRelocationView.chooseOriginalFolder.localized, systemImage: "folder") { selectFolder() }.disabled(model.busy || checking)
                    }
                    if checking { ProgressView(Messages.AppCustomRunDirectoryRelocationView.checkingDirectory.localized) }
                    if let preview {
                        Divider()
                        Text(Messages.AppCustomRunDirectoryRelocationView.previewInstanceCount(Int64(preview.instances.count)).localized).font(.headline)
                        ForEach(preview.instances) { item in
                            LabeledContent(item.name, value: item.usesDirectory ? Messages.AppCustomRunDirectoryRelocationView.useDirectory.localized : Messages.AppCustomRunDirectoryRelocationView.rememberLocation.localized)
                        }
                        Text(Messages.AppCustomRunDirectoryRelocationView.locationHelp.localized).font(.caption).foregroundStyle(.secondary)
                    }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            HStack {
                if selected != nil { Button(Messages.AppCustomRunDirectoryRelocationView.recheck.localized, systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(checking || model.busy) }
                Spacer()
                Button(Messages.AppCustomRunDirectoryRelocationView.close.localized) { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(Messages.AppCustomRunDirectoryRelocationView.updateDirectory.localized) {
                    if let preview { model.relocateCustomDirectory(preview) { dismiss() } }
                }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
            }
        }.padding(24).frame(width: 630, height: 480)
        .interactiveDismissDisabled(model.busy)
        .task(id: (selected?.path ?? "") + refresh.uuidString) {
            preview = nil; issue = nil
            guard let selected else { return }
            checking = true
            do {
                let value = try await CustomRunDirectoryRelocation(paths: model.paths).preview(instanceID: instanceID, target: selected)
                try Task.checkCancellation(); preview = value
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
    }
    private func selectFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppCustomRunDirectoryRelocationView.chooseOriginalDirectory.localized
        panel.begin { response in if response == .OK, let url = panel.url { selected = url; refresh = UUID() } }
    }
}
