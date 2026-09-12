import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct InstanceCopyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var name: String
    @State private var directoryID: UUID
    @State private var includeWorlds = true
    @State private var includeBackups = false
    @State private var checking = false
    @State private var cancelling = false
    @State private var preview: InstanceCopyPreview?
    @State private var recovery: InstanceCopyRecovery?
    @State private var issue: String?
    @State private var refresh = UUID()
    init(instance: GameInstance) {
        self.instance = instance; _name = State(initialValue: Messages.AppInstanceCopyView.copyName(instance.name).localized)
        _directoryID = State(initialValue: instance.directoryID ?? GameDirectory.defaultID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: recovery == nil ? Messages.AppInstanceCopyView.bodyText1.localized : Messages.AppInstanceCopyView.bodyText2.localized, subtitle: instance.name)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recovery {
                        Label(recovery.committed ? Messages.AppInstanceCopyView.recoveryText1.localized : Messages.AppInstanceCopyView.recoveryText2.localized, systemImage: "arrow.counterclockwise").font(.headline)
                        Text(Messages.AppInstanceCopyView.recoveryText3(String(describing: recovery.destination.path)).localized).font(.caption).textSelection(.enabled)
                        Text(recovery.committed ? Messages.AppInstanceCopyView.recoveryText4.localized : Messages.AppInstanceCopyView.recoveryText5.localized).font(.callout).foregroundStyle(.secondary)
                        Button(Messages.AppInstanceCopyView.recoveryText6.localized, systemImage: "folder") { NSWorkspace.shared.open(recovery.workspace) }
                    } else {
                        TextField(Messages.AppInstanceCopyView.recoveryText7.localized, text: $name).textFieldStyle(.roundedBorder).disabled(model.busy)
                        Picker(Messages.AppInstanceCopyView.recoveryText8.localized, selection: $directoryID) {
                            Text(Messages.AppInstanceCopyView.recoveryText9.localized).tag(GameDirectory.defaultID)
                            ForEach(model.state.gameDirectories ?? []) { Text($0.name).tag($0.id) }
                        }.disabled(model.busy)
                        Button(Messages.AppInstanceCopyView.recoveryText10.localized, systemImage: "folder.badge.plus") { addDirectory() }.disabled(model.busy || checking)
                        Toggle(Messages.AppInstanceCopyView.recoveryText11.localized, isOn: $includeWorlds).disabled(model.busy)
                        Toggle(Messages.AppInstanceCopyView.recoveryText12.localized, isOn: $includeBackups).disabled(model.busy)
                        Text(instance.repositoryVersionID == nil && instance.importedInstallation == nil
                             ? Messages.AppInstanceCopyView.recoveryText13.localized
                             : Messages.AppInstanceCopyView.recoveryText14.localized)
                            .font(.callout).foregroundStyle(.secondary)
                        if let preview {
                            Divider()
                            LabeledContent(Messages.AppInstanceCopyView.previewText1.localized, value: Messages.Common.filesAndSize(Int64(preview.fileCount), LocalizedFormat.bytes(preview.bytes)).localized)
                            Text(Messages.AppInstanceCopyView.recoveryText3(String(describing: preview.destination.path)).localized).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if !preview.source.installed { Text(Messages.AppInstanceCopyView.previewText3.localized).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if checking { ProgressView(Messages.AppInstanceCopyView.previewText4.localized) }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if model.busy { ProgressView(cancelling ? Messages.AppInstanceCopyView.issueText1.localized : model.activeActivity?.progress.stage ?? Messages.AppInstanceCopyView.issueText2.localized).controlSize(.small) }
            HStack {
                Button(Messages.AppInstanceCopyView.issueText3.localized, systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(checking || model.busy)
                Spacer()
                Button(model.busy ? Messages.AppInstanceCopyView.issueText4.localized : Messages.AppInstanceCopyView.issueText5.localized) {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
                if let recovery {
                    Button(recovery.committed ? Messages.AppInstanceCopyView.recoveryText15.localized : Messages.AppInstanceCopyView.recoveryText16.localized) { model.recoverInstanceCopy(recovery) }.buttonStyle(.borderedProminent).disabled(checking || model.busy)
                } else {
                    Button(Messages.AppInstanceCopyView.recoveryText17.localized) { if let preview { model.copyInstance(preview) { dismiss() } } }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
                }
            }
        }.padding(24).frame(width: 640, height: 535)
        .interactiveDismissDisabled(model.busy)
        .task(id: name + directoryID.uuidString + String(includeWorlds) + String(includeBackups) + refresh.uuidString) {
            preview = nil; recovery = nil; issue = nil; checking = true
            do {
                try await Task.sleep(for: .milliseconds(250))
                let service = InstanceCopier(paths: model.paths)
                if let pending = try await service.pending(instanceID: instance.id) { try Task.checkCancellation(); recovery = pending }
                else {
                    let result = try await service.preview(instanceID: instance.id, name: name, directoryID: directoryID, options: .init(includeWorlds: includeWorlds, includeBackups: includeBackups))
                    try Task.checkCancellation(); preview = result
                }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
    }
    private func addDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppInstanceCopyView.panelText1.localized
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.changeDirectory { try MinecraftFolderStore.add(name: String(url.lastPathComponent.prefix(100)), url: url, paths: $0) }
            if let added = model.state.gameDirectories?.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.resolvingSymlinksInPath().path }) { directoryID = added.id }
        }
    }
}
