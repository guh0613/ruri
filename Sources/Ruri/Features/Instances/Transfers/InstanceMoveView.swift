import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct InstanceMoveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var directoryID: UUID?
    @State private var preview: InstanceMovePreview?
    @State private var recovery: InstanceMoveRecovery?
    @State private var checking = false
    @State private var cancelling = false
    @State private var issue: String?
    @State private var operationIssue: String?
    @State private var refresh = UUID()
    private var source: GameInstance { model.state.instances.first { $0.id == instance.id } ?? instance }
    private var choices: [UUID] { ([GameDirectory.defaultID] + (model.state.gameDirectories ?? []).map(\.id)).filter { $0 != (source.directoryID ?? GameDirectory.defaultID) } }
    private func directoryName(_ id: UUID) -> String {
        id == GameDirectory.defaultID ? Messages.AppInstanceMoveView.directoryNameText1.localized : model.state.gameDirectories?.first(where: { $0.id == id })?.name ?? Messages.AppInstanceMoveView.directoryNameText2.localized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: recovery == nil ? Messages.AppInstanceMoveView.bodyText1.localized : Messages.AppInstanceMoveView.bodyText2.localized, subtitle: source.name)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recovery {
                        Label(recovery.committed ? Messages.AppInstanceMoveView.recoveryText1.localized : Messages.AppInstanceMoveView.recoveryText2.localized, systemImage: "arrow.counterclockwise").font(.headline)
                        path(Messages.AppInstanceMoveView.recoveryText3.localized, recovery.source)
                        path(Messages.AppInstanceMoveView.recoveryText4.localized, recovery.destination)
                        Text(recovery.committed ? Messages.AppInstanceMoveView.recoveryText5.localized : Messages.AppInstanceMoveView.recoveryText6.localized).font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(Messages.AppInstanceMoveView.recoveryText7.localized, systemImage: "folder") { reveal(recovery.workspace) }
                            Button(Messages.AppInstanceMoveView.recoveryText8.localized, systemImage: "folder") { reveal(recovery.retiredSource ?? recovery.source) }
                            Button(Messages.AppInstanceMoveView.recoveryText9.localized, systemImage: "folder") { reveal(recovery.destination) }
                        }.disabled(model.busy)
                    } else {
                        LabeledContent(Messages.AppInstanceMoveView.recoveryText10.localized, value: directoryName(source.directoryID ?? GameDirectory.defaultID))
                        Picker(Messages.AppInstanceMoveView.recoveryText11.localized, selection: $directoryID) {
                            if directoryID == nil { Text(Messages.AppInstanceMoveView.recoveryText12.localized).tag(UUID?.none) }
                            ForEach(choices, id: \.self) { id in Text(directoryName(id)).tag(Optional(id)) }
                        }.disabled(model.busy)
                        Button(Messages.AppInstanceMoveView.recoveryText13.localized, systemImage: "folder.badge.plus", action: addDirectory).disabled(model.busy || checking)
                        Text(source.importedInstallation == nil && source.repositoryVersionID == nil
                             ? Messages.AppInstanceMoveView.recoveryText14.localized
                             : Messages.AppInstanceMoveView.recoveryText15.localized)
                            .font(.callout).foregroundStyle(.secondary)
                        switch source.runDirectory ?? .isolated {
                        case .isolated: Text(Messages.AppInstanceMoveView.recoveryText16.localized)
                        case .shared: Text(Messages.AppInstanceMoveView.recoveryText17.localized)
                        case .custom: Text(Messages.AppInstanceMoveView.recoveryText18.localized)
                        }
                        if let preview {
                            Divider()
                            LabeledContent(Messages.AppInstanceMoveView.previewText1.localized, value: Messages.Common.filesAndSize(Int64(preview.fileCount), LocalizedFormat.bytes(preview.bytes)).localized)
                            path(Messages.AppInstanceMoveView.previewText3.localized, preview.destination)
                            if let kept = preview.retainedGameDirectory { path(Messages.AppInstanceMoveView.keptText1.localized, kept) }
                            if let prior = preview.preservedPreviousData {
                                Text(Messages.AppInstanceMoveView.priorText1.localized).font(.caption).foregroundStyle(.secondary)
                                path(Messages.AppInstanceMoveView.priorText2.localized, prior)
                            }
                        }
                    }
                    if checking { ProgressView(Messages.AppInstanceMoveView.priorText3.localized) }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if let operationIssue { Label(operationIssue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if model.busy {
                ProgressView(model.activeActivity?.progress.stage ?? Messages.AppInstanceMoveView.operationIssueText1.localized, value: model.activeActivity?.progress.fraction).controlSize(.small)
                if cancelling { Text(Messages.AppInstanceMoveView.operationIssueText2.localized).font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Button(Messages.AppInstanceMoveView.operationIssueText3.localized, systemImage: "arrow.clockwise") { operationIssue = nil; refresh = UUID() }.disabled(checking || model.busy)
                Spacer()
                Button(model.busy ? Messages.Common.cancel.localized : Messages.AppInstanceMoveView.operationIssueText4.localized) {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling)
                if let recovery {
                    if recovery.committed {
                        Menu(Messages.AppInstanceMoveView.recoveryText19.localized) {
                            Button(Messages.AppInstanceMoveView.recoveryText20.localized) { recover(recovery, preserving: false) }
                            Button(Messages.AppInstanceMoveView.recoveryText21.localized) { recover(recovery, preserving: true) }
                        } primaryAction: { recover(recovery, preserving: false) }
                        .menuStyle(.borderedButton).fixedSize().disabled(checking || model.busy)
                    } else {
                        Button(Messages.AppInstanceMoveView.recoveryText22.localized) { recover(recovery, preserving: false) }.buttonStyle(.borderedProminent).disabled(checking || model.busy)
                    }
                } else {
                    Button(Messages.AppInstanceMoveView.bodyText1.localized) {
                        if let preview { operationIssue = nil; model.moveInstance(preview, failed: { operationIssue = $0 }) { dismiss() } }
                    }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
                }
            }
        }.padding(24).frame(width: 660, height: 535)
        .interactiveDismissDisabled(model.busy)
        .onAppear { if directoryID == nil { directoryID = choices.first } }
        .task(id: (directoryID?.uuidString ?? "") + refresh.uuidString) {
            preview = nil; recovery = nil; issue = nil; checking = true
            do {
                try await Task.sleep(for: .milliseconds(200))
                let service = InstanceMover(paths: model.basePaths)
                if let pending = try await service.pending(instanceID: instance.id) { try Task.checkCancellation(); recovery = pending }
                else if let directoryID {
                    let value = try await service.preview(instanceID: instance.id, directoryID: directoryID)
                    try Task.checkCancellation(); preview = value
                } else { issue = Messages.AppInstanceMoveView.valueText1.localized }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
        .onChange(of: directoryID) { operationIssue = nil }
    }
    private func path(_ label: String, _ url: URL) -> some View { Text("\(label)：\(url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { issue = Messages.AppInstanceMoveView.revealText1(String(describing: url.path)).localized }
    }
    private func recover(_ pending: InstanceMoveRecovery, preserving: Bool) {
        operationIssue = nil
        model.recoverInstanceMove(pending, preservingSource: preserving, failed: { operationIssue = $0 }) { dismiss() }
    }
    private func addDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.message = Messages.AppInstanceMoveView.panelText1.localized
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.changeDirectory { try MinecraftFolderStore.add(name: String(url.lastPathComponent.prefix(100)), url: url, paths: $0) }
            if let added = model.state.gameDirectories?.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.resolvingSymlinksInPath().path }) { directoryID = added.id }
        }
    }
}
