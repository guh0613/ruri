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
            SectionHeading(title: recovery == nil ? Messages.AppGameRunDirectoryChangeView.bodyText1.localized : Messages.AppGameRunDirectoryChangeView.bodyText2.localized, subtitle: recovery?.owner.instanceName ?? (instance.name + " · " + instance.subtitle))
            if recovery == nil {
                Picker(Messages.AppGameRunDirectoryChangeView.bodyText3.localized, selection: $target) { ForEach(GameRunDirectory.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.busy || registering)
                Text(target.explanation).font(.callout).foregroundStyle(.secondary)
                if target == .custom {
                    HStack {
                        Text(customDirectory?.url.path ?? Messages.AppGameRunDirectoryChangeView.bodyText4.localized).font(.caption).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button(Messages.AppGameRunDirectoryChangeView.bodyText5.localized) {
                            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
                            panel.message = Messages.AppGameRunDirectoryChangeView.panelText1.localized
                            if panel.runModal() == .OK, let url = panel.url { chosenURL = url; selectionRequest = UUID() }
                        }.disabled(model.busy || registering)
                    }
                }
            }
            if loading || registering { ProgressView(registering ? Messages.AppGameRunDirectoryChangeView.urlText1.localized : Messages.AppGameRunDirectoryChangeView.urlText2.localized).frame(maxWidth: .infinity, minHeight: 220) }
            else if let recovery {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(recovery.committed ? Messages.AppGameRunDirectoryChangeView.recoveryText1.localized : Messages.AppGameRunDirectoryChangeView.recoveryText2.localized, systemImage: "arrow.counterclockwise.circle").font(.headline)
                        Text(recovery.committed ? Messages.AppGameRunDirectoryChangeView.recoveryText3.localized : Messages.AppGameRunDirectoryChangeView.recoveryText4.localized)
                        Text(Messages.AppGameRunDirectoryChangeView.recoveryText5(String(describing: LocalizedFormat.date(recovery.createdAt, date: .abbreviated, time: .shortened))).localized).font(.caption).foregroundStyle(.secondary)
                        Text(Messages.AppGameRunDirectoryChangeView.recoveryText6(String(describing: recovery.source.path), String(describing: recovery.target.path)).localized).font(.caption).textSelection(.enabled)
                        Button(Messages.AppGameRunDirectoryChangeView.recoveryText7.localized) { NSWorkspace.shared.open(recovery.workspace) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                }
            }
            else if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker(Messages.AppGameRunDirectoryChangeView.previewText1.localized, selection: $copyFiles) {
                            Text(Messages.AppGameRunDirectoryChangeView.previewText2.localized).tag(false)
                            Text(Messages.AppGameRunDirectoryChangeView.previewText3.localized).tag(true).disabled(!preview.canCopyToTarget)
                        }.pickerStyle(.radioGroup).disabled(model.busy)
                        if let issue = preview.copyIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        else if !preview.canCopyToTarget { Text(Messages.AppGameRunDirectoryChangeView.issueText1.localized).font(.caption).foregroundStyle(.secondary) }
                        location(Messages.AppGameRunDirectoryChangeView.issueText2.localized, url: preview.source, files: preview.sourceFileCount, bytes: preview.sourceBytes)
                        location(Messages.AppGameRunDirectoryChangeView.issueText3.localized, url: preview.target, files: preview.targetFileCount, bytes: preview.targetBytes)
                        if !preview.otherInstances.isEmpty {
                            Text(Messages.AppGameRunDirectoryChangeView.sharedInstances(LocalizedFormat.list(preview.otherInstances)).localized).font(.callout).foregroundStyle(.secondary)
                        }
                        Text(copyFiles ? Messages.AppGameRunDirectoryChangeView.issueText5.localized : preview.targetFileCount == 0 ? Messages.AppGameRunDirectoryChangeView.issueText6.localized : Messages.AppGameRunDirectoryChangeView.issueText7.localized)
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text(Messages.AppGameRunDirectoryChangeView.issueText8.localized).font(.caption).foregroundStyle(.secondary)
                        if instance.repositoryVersionID != nil { Text(Messages.AppGameRunDirectoryChangeView.issueText9.localized).font(.caption).foregroundStyle(.secondary) }
                    }.padding(2)
                }.frame(minHeight: 230)
            } else if let issue {
                VStack(alignment: .leading, spacing: 12) {
                    Label(Messages.AppGameRunDirectoryChangeView.issueText10.localized, systemImage: "exclamationmark.triangle").font(.headline)
                    Text(issue).font(.callout).textSelection(.enabled)
                    Button(Messages.AppGameRunDirectoryChangeView.issueText11.localized) { refresh = UUID() }
                }.frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            }
            HStack {
                Button(Messages.AppGameRunDirectoryChangeView.issueText12.localized, systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(loading || registering || model.busy)
                Spacer()
                Button(model.busy ? Messages.AppGameRunDirectoryChangeView.issueText13.localized : Messages.AppGameRunDirectoryChangeView.issueText14.localized) {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
                if let recovery {
                    Button(recovery.committed ? Messages.AppGameRunDirectoryChangeView.recoveryText8.localized : Messages.AppGameRunDirectoryChangeView.recoveryText9.localized) { model.recoverGameRunDirectory(recovery) }.buttonStyle(.borderedProminent).disabled(model.busy || loading || registering)
                } else {
                    Button(copyFiles ? Messages.AppGameRunDirectoryChangeView.recoveryText10.localized : Messages.AppGameRunDirectoryChangeView.recoveryText11.localized) { if let preview { model.changeGameRunDirectory(preview, copyFiles: copyFiles) } }
                        .buttonStyle(.borderedProminent).disabled(preview == nil || loading || registering || model.busy)
                }
            }
            if model.busy { ProgressView(cancelling ? Messages.AppGameRunDirectoryChangeView.previewText4.localized : model.activeActivity?.progress.stage ?? Messages.AppGameRunDirectoryChangeView.previewText5.localized).controlSize(.small) }
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
            Text(Messages.AppGameRunDirectoryChangeView.locationText1(Int64(files), String(describing: LocalizedFormat.bytes(bytes))).localized).font(.caption)
            Button(Messages.AppGameRunDirectoryChangeView.locationText2.localized) { NSWorkspace.shared.open(url) }.buttonStyle(.link).disabled(!FileManager.default.fileExists(atPath: url.path))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
