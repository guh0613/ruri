import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct InstanceSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var instance: GameInstance
    @State private var pane = InstanceSettingsPane.overview
    @State private var changingDirectory = false
    @State private var relocatingDirectory = false
    @State private var copyingInstance = false
    @State private var movingInstance = false
    @State private var managingComponents = false
    @State private var updatingModpack = false
    @State private var launchOverrides: InstanceLaunchOverrides
    @State private var settingsIssue: String?
    @State private var loadingIcon = false
    @State private var choosingIcon = false
    @State private var modpackOrigin: ModpackOrigin?
    @State private var preservedWorkspaces: [URL] = []
    private let original: GameInstance
    private var locationInstance: GameInstance { model.state.instances.first(where: { $0.id == instance.id }) ?? instance }
    private var directoryCopyPending: Bool { model.pendingDirectoryCopyIDs.contains(instance.id) || RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) }
    init(instance: GameInstance) { _instance = State(initialValue: instance); _launchOverrides = State(initialValue: instance.effectiveLaunchOverrides); original = instance }
    private var hasChanges: Bool {
        instance.name != original.name || instance.favorite != original.favorite || instance.iconPNG != original.iconPNG || instance.iconStyle != original.iconStyle || launchOverrides != original.effectiveLaunchOverrides
    }
    var body: some View {
        VStack(spacing: 0) {
            SettingsLayout(title: Messages.AppInstanceSettingsView.instanceSettings.localized, subtitle: instance.name, selection: $pane) {
                switch pane {
                case .overview: overview
                case .files: files
                default:
                    if pane == .runtime, let versions = instance.supportedJavaMajors, !versions.isEmpty {
                        Section { LabeledContent(Messages.AppInstanceSettingsView.supportedJava.localized, value: LocalizedFormat.list(versions.map(String.init))) }
                    }
                    LaunchSettingsEditor(overrides: $launchOverrides, defaults: model.state.settings.defaultLaunchSettings, runtimes: model.runtimes, keys: pane.launchKeys)
                }
            }
            Divider()
            if let settingsIssue {
                Label(settingsIssue, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 12)
            }
            HStack(spacing: 12) {
                if hasChanges {
                    Text(Messages.AppInstanceSettingsView.unsavedChanges.localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppInstanceSettingsView.save.localized, action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!hasChanges || loadingIcon || model.readOnly)
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 860, height: 670)
        .interactiveDismissDisabled(hasChanges)
        .onChange(of: launchOverrides) { _, _ in settingsIssue = nil }
        .onChange(of: instance.name) { _, _ in settingsIssue = nil }
        .sheet(isPresented: $changingDirectory) { GameRunDirectoryChangeView(instance: locationInstance) }
        .sheet(isPresented: $relocatingDirectory) { CustomRunDirectoryRelocationView(instanceID: instance.id) }
        .sheet(isPresented: $copyingInstance) { InstanceCopyView(instance: locationInstance) }
        .sheet(isPresented: $movingInstance) { InstanceMoveView(instance: locationInstance) }
        .sheet(isPresented: $managingComponents) { InstanceComponentsView(instance: locationInstance) }
        .sheet(isPresented: $updatingModpack) { ModpackUpdateView(instance: locationInstance) }
        .task(id: model.busy) {
            guard !model.busy else { return }
            let paths = model.paths, id = instance.id
            let locations = await Task.detached(priority: .utility) {
                RunDirectoryCopyGuard.preservedWorkspaces(paths: paths, instanceID: id) + InstanceCopyGuard.preservedWorkspaces(paths: paths, sourceID: id) + InstanceMoveGuard.preservedWorkspaces(paths: paths, instanceID: id)
            }.value
            if !Task.isCancelled { preservedWorkspaces = locations }
        }
        .task {
            let paths = model.paths, id = instance.id
            let origin = await Task.detached(priority: .utility) { try? ModpackRegistry.load(paths: paths, instanceID: id)?.origin }.value
            if let origin, origin.provider != .mcbbs, origin.projectID != nil { modpackOrigin = origin }
        }
    }
    @ViewBuilder private var overview: some View {
        Section(Messages.AppInstanceSettingsView.instanceInfo.localized) {
            HStack(spacing: 20) {
                Text(Messages.AppInstanceSettingsView.nameLabel.localized).fixedSize()
                TextField(Messages.AppInstanceSettingsView.instanceName.localized, text: $instance.name, prompt: Text(Messages.AppInstanceSettingsView.enterInstanceName.localized))
                    .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity).accessibilityLabel(Messages.AppInstanceSettingsView.instanceName.localized)
            }
            Toggle(Messages.AppInstanceSettingsView.favoriteInstance.localized, isOn: $instance.favorite)
            HStack(spacing: 14) {
                Button { choosingIcon = true } label: {
                    InstanceIcon(loader: locationInstance.loader, size: 52, png: instance.iconPNG, style: instance.iconStyle)
                }
                .buttonStyle(.plain).disabled(loadingIcon)
                .help(Messages.AppInstanceSettingsView.changeIcon.localized)
                .accessibilityLabel(Messages.AppInstanceSettingsView.changeIcon.localized)
                .popover(isPresented: $choosingIcon, arrowEdge: .bottom) {
                    InstanceIconPicker(loader: locationInstance.loader, png: $instance.iconPNG, style: $instance.iconStyle,
                                       chooseImage: { choosingIcon = false; chooseIcon() },
                                       useModpackIcon: modpackOrigin.map { origin in { choosingIcon = false; useModpackIcon(origin) } })
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(Messages.AppInstanceSettingsView.instanceIcon.localized)
                    Text(Messages.AppInstanceSettingsView.iconCropNotice.localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loadingIcon { ProgressView().controlSize(.small) }
                VStack(alignment: .trailing, spacing: 6) {
                    Button(Messages.AppInstanceSettingsView.changeIcon.localized) { choosingIcon = true }
                    if instance.iconPNG != nil || instance.iconStyle != nil {
                        Button(Messages.AppInstanceSettingsView.restoreDefaultIcon.localized) { instance.iconPNG = nil; instance.iconStyle = nil }
                            .buttonStyle(.borderless).font(.caption)
                    }
                }.fixedSize().disabled(loadingIcon)
            }.padding(.vertical, 5)
        }
        Section(Messages.AppInstanceSettingsView.gameComponents.localized) {
            LabeledContent("Minecraft", value: locationInstance.gameVersion)
            SettingsActionRow(title: Messages.AppInstanceSettingsView.loader.localized, detail: locationInstance.subtitle, button: Messages.AppInstanceSettingsView.manageComponents.localized) { managingComponents = true }
                .disabled(model.busy || model.isInstanceInUse(instance.id) || !locationInstance.installed)
            SettingsActionRow(title: Messages.AppInstanceSettingsView.packUpdate.localized, detail: Messages.AppInstanceSettingsView.packUpdateDescription.localized, button: Messages.AppInstanceSettingsView.viewPackUpdate.localized) { updatingModpack = true }
                .disabled(model.busy || (!ModpackUpdateStore.hasPending(paths: model.paths, instanceID: instance.id) && model.isInstanceInUse(instance.id)))
        }
        Section {
            SettingsActionRow(title: Messages.AppInstanceSettingsView.defaultLaunchSettings.localized,
                              detail: Messages.AppInstanceSettingsView.restoreInheritedSettings.localized,
                              button: Messages.AppInstanceSettingsView.restoreLaunchSettings.localized) {
                launchOverrides = .init()
                settingsIssue = nil
            }.disabled(LaunchSettingKey.allCases.allSatisfy { launchOverrides.inherits($0) })
        }
    }
    @ViewBuilder private var files: some View {
        Section(Messages.AppInstanceSettingsView.runDirectory.localized) {
            LabeledContent(Messages.AppInstanceSettingsView.saveMethod.localized, value: (locationInstance.runDirectory ?? .isolated).title)
            VStack(alignment: .leading, spacing: 6) {
                Text((locationInstance.runDirectory ?? .isolated).explanation).font(.caption).foregroundStyle(.secondary)
                Text(model.paths.game(instance.id).path).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.customDirectoryErrors[instance.id] { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            LabeledContent(Messages.AppInstanceSettingsView.locationAndIsolation.localized) {
                Button(directoryCopyPending ? Messages.AppInstanceSettingsView.recoverDirectoryCopy.localized : Messages.AppInstanceSettingsView.switchRunDirectory.localized) { changingDirectory = true }
                    .disabled(model.busy || (!directoryCopyPending && model.isInstanceInUse(instance.id)))
            }
            if locationInstance.customRunDirectory != nil {
                Button(locationInstance.runDirectory == .custom ? Messages.AppInstanceSettingsView.relocateOriginalDirectory.localized : Messages.AppInstanceSettingsView.relocateCustomDirectory.localized) { relocatingDirectory = true }.disabled(model.busy)
            }
            HStack {
                Button(Messages.AppInstanceSettingsView.openFolder.localized, systemImage: "folder") { model.reveal(locationInstance) }
                Spacer()
                Button(Messages.AppInstanceSettingsView.mods.localized) { model.reveal(locationInstance, folder: "mods") }
                Button(Messages.AppInstanceSettingsView.worlds.localized) { model.reveal(locationInstance, folder: "saves") }
            }
        }
        Section {
            if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.incompleteCopy.localized, detail: Messages.AppInstanceSettingsView.incompleteCopyDescription.localized, button: Messages.AppInstanceSettingsView.recover.localized) { copyingInstance = true }.disabled(model.busy)
            } else {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.copyInstance.localized, detail: Messages.AppInstanceSettingsView.copyDescription.localized, button: Messages.AppInstanceSettingsView.copy.localized) { copyingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
            }
            if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.incompleteMove.localized, detail: Messages.AppInstanceSettingsView.incompleteMoveDescription.localized, button: Messages.AppInstanceSettingsView.recover.localized) { movingInstance = true }.disabled(model.busy)
            } else {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.moveInstance.localized, detail: Messages.AppInstanceSettingsView.moveDescription.localized, button: Messages.AppInstanceSettingsView.move.localized) { movingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
            }
        } header: { Text(Messages.AppInstanceSettingsView.copyAndMove.localized) } footer: { Text(Messages.AppInstanceSettingsView.fileOperationNotice.localized) }
        if !preservedWorkspaces.isEmpty {
            Section(Messages.AppInstanceSettingsView.retainedWorkFiles.localized) {
                ForEach(Array(preservedWorkspaces.enumerated()), id: \.offset) { index, url in
                    LabeledContent(Messages.AppInstanceSettingsView.copyLabel(String(describing: index + 1)).localized) { Button(Messages.AppInstanceSettingsView.viewInFinder.localized) { NSWorkspace.shared.open(url) } }
                }
            }
        }
    }
    private func save() {
        guard !instance.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { pane = .overview; settingsIssue = Messages.AppInstanceSettingsView.nameRequired.localized; return }
        let effective = launchOverrides.resolve(defaults: model.state.settings.defaultLaunchSettings)
        if let issue = SettingsValidation.issue(in: effective) { pane = .containing(issue.key); settingsIssue = issue.message; return }
        instance.launchOverrides = launchOverrides
        if model.updateSettings(instance, basedOn: original) { dismiss() }
        else { settingsIssue = model.error ?? Messages.AppInstanceSettingsView.instanceMissing.localized }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = Messages.AppInstanceSettingsView.chooseIcon.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadingIcon = true
        Task {
            defer { loadingIcon = false }
            do {
                instance.iconPNG = try await Task.detached(priority: .userInitiated) { try InstanceIconImage.load(url) }.value
                instance.iconStyle = nil
            }
            catch { settingsIssue = error.localizedDescription }
        }
    }

    private func useModpackIcon(_ origin: ModpackOrigin) {
        guard let projectID = origin.projectID else { return }
        loadingIcon = true
        Task {
            defer { loadingIcon = false }
            var url: URL?
            if origin.provider == .modrinth { url = try? await ModrinthService().project(projectID).icon_url }
            else if let id = Int(projectID) { url = try? await CurseForgeService(apiKey: CurseForgeKeyStore.load()).project(id).logo?.thumbnailUrl }
            if let png = await InstanceIconImage.download(url) { instance.iconPNG = png; instance.iconStyle = nil }
            else { settingsIssue = Messages.AppInstanceIconPicker.modpackIconUnavailable.localized }
        }
    }
}
