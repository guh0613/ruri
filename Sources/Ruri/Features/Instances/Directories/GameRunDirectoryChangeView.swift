import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct GameRunDirectoryChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var target: GameRunDirectory
    @State private var customDirectory: CustomRunDirectory?
    @State private var chosenURL: URL?
    @State private var selectionRequest = UUID()
    @State private var registering = false
    @State private var preview: GameRunDirectoryChangePreview?
    @State private var recovery: RunDirectoryCopyRecovery?
    @State private var copyFiles = false
    @State private var choiceFor: String?
    @State private var cancelling = false
    @State private var loading = false
    @State private var issue: String?
    @State private var refresh = UUID()
    init(instance: GameInstance) {
        self.instance = instance
        _target = State(initialValue: (instance.runDirectory ?? .isolated) == .isolated ? .shared : .isolated)
        _customDirectory = State(initialValue: instance.customRunDirectory)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: recovery == nil ? Messages.AppGameRunDirectoryChangeView.changeRunDirectory.localized : Messages.AppGameRunDirectoryChangeView.recoverDirectoryCopy.localized, subtitle: recovery?.owner.instanceName ?? (instance.name + " · " + instance.subtitle))
            if recovery == nil {
                Picker(Messages.AppGameRunDirectoryChangeView.target.localized, selection: $target) { ForEach(GameRunDirectory.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.busy || registering)
                Text(target.explanation).font(.callout).foregroundStyle(.secondary)
                if target == .custom {
                    HStack {
                        Text(customDirectory?.url.path ?? Messages.AppGameRunDirectoryChangeView.noFolderSelected.localized).font(.caption).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button(Messages.AppGameRunDirectoryChangeView.chooseFolder.localized) {
                            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
                            panel.message = Messages.AppGameRunDirectoryChangeView.directoryPurpose.localized
                            if panel.runModal() == .OK, let url = panel.url { chosenURL = url; selectionRequest = UUID() }
                        }.disabled(model.busy || registering)
                    }
                }
            }
            if loading || registering { ProgressView(registering ? Messages.AppGameRunDirectoryChangeView.preparingSelectedDirectory.localized : Messages.AppGameRunDirectoryChangeView.checkingDirectoryFiles.localized).frame(maxWidth: .infinity, minHeight: 220) }
            else if let recovery {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(recovery.committed ? Messages.AppGameRunDirectoryChangeView.copySubmittedAwaitingCleanup.localized : Messages.AppGameRunDirectoryChangeView.copyIncomplete.localized, systemImage: "arrow.counterclockwise.circle").font(.headline)
                        Text(recovery.committed ? Messages.AppGameRunDirectoryChangeView.recoveryCleanupDetails.localized : Messages.AppGameRunDirectoryChangeView.recoveryPreservationDetails.localized)
                        Text(Messages.AppGameRunDirectoryChangeView.copyStartedAt(String(describing: LocalizedFormat.date(recovery.createdAt, date: .abbreviated, time: .shortened))).localized).font(.caption).foregroundStyle(.secondary)
                        Text(Messages.AppGameRunDirectoryChangeView.sourceAndTargetDirectories(recovery.source.path, recovery.target.path).localized).font(.caption).textSelection(.enabled)
                        Button(Messages.AppGameRunDirectoryChangeView.viewWorkspaceInFinder.localized) { NSWorkspace.shared.open(recovery.workspace) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                }
            }
            else if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker(Messages.AppGameRunDirectoryChangeView.contentHandling.localized, selection: $copyFiles) {
                            Text(Messages.AppGameRunDirectoryChangeView.useExistingContent.localized).tag(false)
                            Text(Messages.AppGameRunDirectoryChangeView.copyCurrentContentToEmptyTarget.localized).tag(true).disabled(!preview.canCopyToTarget)
                        }.pickerStyle(.radioGroup).disabled(model.busy)
                        if let issue = preview.copyIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        else if !preview.canCopyToTarget { Text(Messages.AppGameRunDirectoryChangeView.targetContainsFiles.localized).font(.caption).foregroundStyle(.secondary) }
                        location(Messages.AppGameRunDirectoryChangeView.sourceDirectory.localized, url: preview.source, files: preview.sourceFileCount, bytes: preview.sourceBytes)
                        location(Messages.AppGameRunDirectoryChangeView.targetDirectory.localized, url: preview.target, files: preview.targetFileCount, bytes: preview.targetBytes)
                        if !preview.otherInstances.isEmpty {
                            Text(Messages.AppGameRunDirectoryChangeView.sharedInstances(LocalizedFormat.list(preview.otherInstances)).localized).font(.callout).foregroundStyle(.secondary)
                        }
                        Text(copyFiles ? Messages.AppGameRunDirectoryChangeView.copyBeforeSwitching.localized : preview.targetFileCount == 0 ? Messages.AppGameRunDirectoryChangeView.emptyTargetDetails.localized : Messages.AppGameRunDirectoryChangeView.useExistingTargetDetails.localized)
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(Messages.AppGameRunDirectoryChangeView.fileStatistics.localized).font(.caption).foregroundStyle(.secondary)
                        if instance.repositoryVersionID != nil { Text(Messages.AppGameRunDirectoryChangeView.gameFilesStayInPlace.localized).font(.caption).foregroundStyle(.secondary) }
                    }.padding(2)
                }.frame(minHeight: 230)
            } else if let issue {
                VStack(alignment: .leading, spacing: 12) {
                    Label(Messages.AppGameRunDirectoryChangeView.switchUnavailable.localized, systemImage: "exclamationmark.triangle").font(.headline)
                    Text(issue).font(.callout).textSelection(.enabled)
                    Button(Messages.AppGameRunDirectoryChangeView.recheck.localized) { refresh = UUID() }
                }.frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            }
            HStack {
                Button(Messages.AppGameRunDirectoryChangeView.refreshPreview.localized, systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(loading || registering || model.busy)
                Spacer()
                Button(model.busy ? Messages.AppGameRunDirectoryChangeView.cancelOperation.localized : Messages.AppGameRunDirectoryChangeView.close.localized) {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
                if let recovery {
                    Button(recovery.committed ? Messages.AppGameRunDirectoryChangeView.cleanCompletedRecord.localized : Messages.AppGameRunDirectoryChangeView.recoverAndKeepCopy.localized) { model.recoverGameRunDirectory(recovery) }.buttonStyle(.borderedProminent).disabled(model.busy || loading || registering)
                } else {
                    Button(copyFiles ? Messages.AppGameRunDirectoryChangeView.copyAndSwitch.localized : Messages.AppGameRunDirectoryChangeView.useExistingTargetContent.localized) { if let preview { model.changeGameRunDirectory(preview, copyFiles: copyFiles) } }
                        .buttonStyle(.borderedProminent).disabled(preview == nil || loading || registering || model.busy)
                }
            }
            if model.busy { ProgressView(cancelling ? Messages.AppGameRunDirectoryChangeView.cancellingAndKeepingWorkCopy.localized : model.activeActivity?.progress.stage ?? Messages.AppGameRunDirectoryChangeView.processingDirectory.localized).controlSize(.small) }
        }.padding(24).frame(width: 640, height: 590)
        .interactiveDismissDisabled(model.busy)
        .task(id: selectionRequest) {
            guard let chosenURL else { return }
            registering = true; issue = nil
            let paths = model.paths
            do {
                let selected = try await Task.detached(priority: .userInitiated) { try CustomRunDirectory.register(at: chosenURL, paths: paths) }.value
                try Task.checkCancellation(); customDirectory = selected; refresh = UUID()
            } catch { if !Task.isCancelled { preview = nil; issue = error.localizedDescription } }
            if !Task.isCancelled { registering = false }
        }
        .task(id: target.rawValue + (customDirectory?.url.path ?? "") + refresh.uuidString) {
            preview = nil; recovery = nil; issue = nil; loading = true
            do {
                let service = GameRunDirectoryChange(paths: model.paths)
                if let pending = try await service.pendingCopy(instanceID: instance.id) { try Task.checkCancellation(); recovery = pending }
                else {
                    let result = try await service.preview(instanceID: instance.id, target: target, customDirectory: customDirectory)
                    try Task.checkCancellation(); preview = result
                    let choice = target.rawValue + result.target.path
                    if choiceFor != choice { copyFiles = result.canCopyToTarget && result.sourceFileCount > 0; choiceFor = choice }
                    else if !result.canCopyToTarget { copyFiles = false }
                }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
        .onChange(of: model.paths.game(instance.id)) {
            if model.state.instances.first(where: { $0.id == instance.id })?.runDirectory == target,
               (target != .custom || model.state.instances.first(where: { $0.id == instance.id })?.customRunDirectory?.id == customDirectory?.id),
               !RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) { dismiss() }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
    }
    private func location(_ title: String, url: URL, files: Int, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(Messages.AppGameRunDirectoryChangeView.fileCountAndSize(Int64(files), String(describing: LocalizedFormat.bytes(bytes))).localized).font(.caption)
            Button(Messages.AppGameRunDirectoryChangeView.showInFinder.localized) { NSWorkspace.shared.open(url) }.buttonStyle(.link).disabled(!FileManager.default.fileExists(atPath: url.path))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
