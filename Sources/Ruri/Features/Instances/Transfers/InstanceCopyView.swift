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
    @State private var addingDirectory = false
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
            SectionHeading(title: recovery == nil ? Messages.AppInstanceCopyView.copyInstance.localized : Messages.AppInstanceCopyView.recoverCopy.localized, subtitle: instance.name)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recovery {
                        Label(recovery.committed ? Messages.AppInstanceCopyView.copyCreated.localized : Messages.AppInstanceCopyView.copyIncomplete.localized, systemImage: "arrow.counterclockwise").font(.headline)
                        Text(Messages.AppInstanceCopyView.targetLabel(recovery.destination.path).localized).font(.caption).textSelection(.enabled)
                        Text(recovery.committed ? Messages.AppInstanceCopyView.copyValidationHelp.localized : Messages.AppInstanceCopyView.recoverCopyHelp.localized).font(.callout).foregroundStyle(.secondary)
                        Button(Messages.AppInstanceCopyView.showWorkspace.localized, systemImage: "folder") { NSWorkspace.shared.open(recovery.workspace) }
                    } else {
                        TextField(Messages.AppInstanceCopyView.copyNameField.localized, text: $name).textFieldStyle(.roundedBorder).disabled(model.busy)
                        Picker(Messages.AppInstanceCopyView.saveTo.localized, selection: $directoryID) {
                            Text(Messages.AppInstanceCopyView.defaultInstanceDirectory.localized).tag(GameDirectory.defaultID)
                            ForEach(model.state.gameDirectories ?? []) { Text($0.name).tag($0.id) }
                        }.disabled(model.busy)
                        Button(Messages.AppInstanceCopyView.addTargetFolder.localized, systemImage: "folder.badge.plus") { addingDirectory = true }.disabled(model.busy || checking)
                        Toggle(Messages.AppInstanceCopyView.copyWorlds.localized, isOn: $includeWorlds).disabled(model.busy)
                        Toggle(Messages.AppInstanceCopyView.copyBackups.localized, isOn: $includeBackups).disabled(model.busy)
                        Text(Messages.AppInstanceCopyView.copyDescription.localized)
                            .font(.callout).foregroundStyle(.secondary)
                        if let preview {
                            Divider()
                            LabeledContent(Messages.AppInstanceCopyView.files.localized, value: Messages.Common.filesAndSize(Int64(preview.fileCount), LocalizedFormat.bytes(preview.bytes)).localized)
                            Text(Messages.AppInstanceCopyView.targetLabel(preview.destination.path).localized).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if !preview.source.installed { Text(Messages.AppInstanceCopyView.pendingInstallDescription.localized).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if checking { ProgressView(Messages.AppInstanceCopyView.checkingInstance.localized) }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if model.busy { ProgressView(cancelling ? Messages.AppInstanceCopyView.cancelingCopy.localized : model.activeActivity?.progress.stage ?? Messages.AppInstanceCopyView.processingInstance.localized).controlSize(.small) }
            HStack {
                Button(Messages.AppInstanceCopyView.refreshPreview.localized, systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(checking || model.busy)
                Spacer()
                Button(model.busy ? Messages.AppInstanceCopyView.cancelCopy.localized : Messages.AppInstanceCopyView.close.localized) {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
                if let recovery {
                    Button(recovery.committed ? Messages.AppInstanceCopyView.validateAndComplete.localized : Messages.AppInstanceCopyView.recoverAndKeepCopy.localized) { model.recoverInstanceCopy(recovery) }.buttonStyle(.borderedProminent).disabled(checking || model.busy)
                } else {
                    Button(Messages.AppInstanceCopyView.createCopy.localized) { if let preview { model.copyInstance(preview) { dismiss() } } }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
                }
            }
        }.padding(24).frame(width: 640, height: 535)
        .sheet(isPresented: $addingDirectory) {
            AddMinecraftFolderView(cancel: { addingDirectory = false }, completed: { id in
                directoryID = id; addingDirectory = false
            })
        }
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
}
