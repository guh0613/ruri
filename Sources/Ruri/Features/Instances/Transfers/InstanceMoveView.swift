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
    @State private var addingDirectory = false
    @State private var checking = false
    @State private var cancelling = false
    @State private var issue: String?
    @State private var operationIssue: String?
    @State private var refresh = UUID()
    private var source: GameInstance { model.state.instances.first { $0.id == instance.id } ?? instance }
    private var choices: [UUID] { ([GameDirectory.defaultID] + (model.state.gameDirectories ?? []).map(\.id)).filter { $0 != (source.directoryID ?? GameDirectory.defaultID) } }
    private func directoryName(_ id: UUID) -> String {
        id == GameDirectory.defaultID ? Messages.AppInstanceMoveView.defaultInstanceDirectory.localized : model.state.gameDirectories?.first(where: { $0.id == id })?.name ?? Messages.AppInstanceMoveView.inaccessibleDirectory.localized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: recovery == nil ? Messages.AppInstanceMoveView.moveInstance.localized : Messages.AppInstanceMoveView.recoverMove.localized, subtitle: source.name)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recovery {
                        Label(recovery.committed ? Messages.AppInstanceMoveView.targetReady.localized : Messages.AppInstanceMoveView.moveIncomplete.localized, systemImage: "arrow.counterclockwise").font(.headline)
                        path(Messages.AppInstanceMoveView.sourceLocation.localized, recovery.source)
                        path(Messages.AppInstanceMoveView.targetLocation.localized, recovery.destination)
                        Text(recovery.committed ? Messages.AppInstanceMoveView.moveValidationHelp.localized : Messages.AppInstanceMoveView.recoverMoveHelp.localized).font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button(Messages.AppInstanceMoveView.showWorkspace.localized, systemImage: "folder") { reveal(recovery.workspace) }
                            Button(Messages.AppInstanceMoveView.showSource.localized, systemImage: "folder") { reveal(recovery.retiredSource ?? recovery.source) }
                            Button(Messages.AppInstanceMoveView.showTarget.localized, systemImage: "folder") { reveal(recovery.destination) }
                        }.disabled(model.busy)
                    } else {
                        LabeledContent(Messages.AppInstanceMoveView.currentFolder.localized, value: directoryName(source.directoryID ?? GameDirectory.defaultID))
                        Picker(Messages.AppInstanceMoveView.moveTo.localized, selection: $directoryID) {
                            if directoryID == nil { Text(Messages.AppInstanceMoveView.chooseTargetFolder.localized).tag(UUID?.none) }
                            ForEach(choices, id: \.self) { id in Text(directoryName(id)).tag(Optional(id)) }
                        }.disabled(model.busy)
                        Button(Messages.AppInstanceMoveView.addTargetFolder.localized, systemImage: "folder.badge.plus", action: { addingDirectory = true }).disabled(model.busy || checking)
                        switch source.runDirectory ?? .isolated {
                        case .isolated: Text(Messages.AppInstanceMoveView.sourceCleanupNotice.localized)
                        case .shared: Text(Messages.AppInstanceMoveView.moveSharedContent.localized)
                        case .custom: Text(Messages.AppInstanceMoveView.moveCustomDirectory.localized)
                        }
                        if let preview {
                            Divider()
                            LabeledContent(Messages.AppInstanceMoveView.moveFiles.localized, value: Messages.Common.filesAndSize(Int64(preview.fileCount), LocalizedFormat.bytes(preview.bytes)).localized)
                            path(Messages.AppInstanceMoveView.moveTargetInstance.localized, preview.destination)
                            if let kept = preview.retainedGameDirectory { path(Messages.AppInstanceMoveView.keepRunDirectory.localized, kept) }
                            if let prior = preview.preservedPreviousData {
                                DisclosureGroup(Messages.AppInstanceMoveView.preservedOriginalFiles.localized) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(Messages.AppInstanceMoveView.previousDirectoryContent.localized)
                                        path(Messages.AppInstanceMoveView.savedLocation.localized, prior)
                                    }.font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                                }
                            }
                        }
                    }
                    if checking { ProgressView(Messages.AppInstanceMoveView.checkingInstance.localized) }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if let operationIssue { Label(operationIssue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if model.busy {
                ProgressView(model.activeActivity?.progress.stage ?? Messages.AppInstanceMoveView.operationMoving.localized, value: model.activeActivity?.progress.fraction).controlSize(.small)
                if cancelling { Text(Messages.AppInstanceMoveView.operationFinishing.localized).font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Button(Messages.AppInstanceMoveView.refresh.localized, systemImage: "arrow.clockwise") { operationIssue = nil; refresh = UUID() }.disabled(checking || model.busy)
                Spacer()
                Button(model.busy ? Messages.Common.cancel.localized : Messages.AppInstanceMoveView.close.localized) {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling)
                if let recovery {
                    if recovery.committed {
                        Menu(Messages.AppInstanceMoveView.completeMove.localized) {
                            Button(Messages.AppInstanceMoveView.validateAndClean.localized) { recover(recovery, preserving: false) }
                            Button(Messages.AppInstanceMoveView.keepSourceAndComplete.localized) { recover(recovery, preserving: true) }
                        } primaryAction: { recover(recovery, preserving: false) }
                        .menuStyle(.borderedButton).fixedSize().disabled(checking || model.busy)
                    } else {
                        Button(Messages.AppInstanceMoveView.recoverAndKeepCopy.localized) { recover(recovery, preserving: false) }.buttonStyle(.borderedProminent).disabled(checking || model.busy)
                    }
                } else {
                    Button(Messages.AppInstanceMoveView.moveInstance.localized) {
                        if let preview { operationIssue = nil; model.moveInstance(preview, failed: { operationIssue = $0 }) { dismiss() } }
                    }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
                }
            }
        }.padding(24).frame(width: 660, height: 535)
        .sheet(isPresented: $addingDirectory) {
            AddMinecraftFolderView(cancel: { addingDirectory = false }, completed: { id in
                directoryID = id; addingDirectory = false
            })
        }
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
                } else { issue = Messages.AppInstanceMoveView.anotherFolderRequired.localized }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
        .onChange(of: directoryID) { operationIssue = nil }
    }
    private func path(_ label: String, _ url: URL) -> some View { Text("\(label)：\(url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { issue = Messages.AppInstanceMoveView.inaccessibleLocation(url.path).localized }
    }
    private func recover(_ pending: InstanceMoveRecovery, preserving: Bool) {
        operationIssue = nil
        model.recoverInstanceMove(pending, preservingSource: preserving, failed: { operationIssue = $0 }) { dismiss() }
    }
}
