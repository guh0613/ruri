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
    @State private var preservedWorkspaces: [URL] = []
    private let original: GameInstance
    private var locationInstance: GameInstance { model.state.instances.first(where: { $0.id == instance.id }) ?? instance }
    private var directoryCopyPending: Bool { model.pendingDirectoryCopyIDs.contains(instance.id) || RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) }
    init(instance: GameInstance) { _instance = State(initialValue: instance); _launchOverrides = State(initialValue: instance.effectiveLaunchOverrides); original = instance }
    private var hasChanges: Bool {
        instance.name != original.name || instance.favorite != original.favorite || instance.iconPNG != original.iconPNG || launchOverrides != original.effectiveLaunchOverrides
    }
    var body: some View {
        VStack(spacing: 0) {
            SettingsLayout(title: Messages.AppInstanceSettingsView.bodyText1.localized, subtitle: instance.name, selection: $pane) {
                switch pane {
                case .overview: overview
                case .files: files
                default:
                    if pane == .runtime, let versions = instance.supportedJavaMajors, !versions.isEmpty {
                        Section { LabeledContent(Messages.AppInstanceSettingsView.versionsText1.localized, value: LocalizedFormat.list(versions.map(String.init))) }
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
                Menu(Messages.AppInstanceSettingsView.settingsIssueText1.localized) { Button(Messages.AppInstanceSettingsView.settingsIssueText2.localized) { launchOverrides = .init(); settingsIssue = nil } }
                    .fixedSize().help(Messages.AppInstanceSettingsView.settingsIssueText3.localized)
                Text(hasChanges ? Messages.AppInstanceSettingsView.settingsIssueText4.localized : Messages.AppInstanceSettingsView.settingsIssueText5.localized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppInstanceSettingsView.settingsIssueText6.localized, action: save).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
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
    }
    @ViewBuilder private var overview: some View {
        Section(Messages.AppInstanceSettingsView.overviewText1.localized) {
            LabeledContent(Messages.AppInstanceSettingsView.overviewText2.localized) {
                TextField(Messages.AppInstanceSettingsView.overviewText3.localized, text: $instance.name, prompt: Text(Messages.AppInstanceSettingsView.overviewText4.localized))
                    .labelsHidden().textFieldStyle(.roundedBorder).frame(minWidth: 220).accessibilityLabel(Messages.AppInstanceSettingsView.overviewText3.localized)
            }
            Toggle(Messages.AppInstanceSettingsView.overviewText5.localized, isOn: $instance.favorite)
            HStack(spacing: 14) {
                InstanceIcon(loader: locationInstance.loader, size: 48, png: instance.iconPNG)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Messages.AppInstanceSettingsView.overviewText6.localized)
                    Text(Messages.AppInstanceSettingsView.overviewText7.localized).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if loadingIcon { ProgressView().controlSize(.small) }
                Menu(Messages.AppInstanceSettingsView.overviewText8.localized) {
                    Button(Messages.AppInstanceSettingsView.overviewText9.localized, action: chooseIcon)
                    if instance.iconPNG != nil { Button(Messages.AppInstanceSettingsView.overviewText10.localized) { instance.iconPNG = nil } }
                }.fixedSize().disabled(loadingIcon)
            }.padding(.vertical, 5)
        }
        Section(Messages.AppInstanceSettingsView.overviewText11.localized) {
            LabeledContent("Minecraft", value: locationInstance.gameVersion)
            SettingsActionRow(title: Messages.AppInstanceSettingsView.overviewText12.localized, detail: locationInstance.subtitle, button: Messages.AppInstanceSettingsView.overviewText13.localized) { managingComponents = true }
                .disabled(model.busy || model.isInstanceInUse(instance.id) || !locationInstance.installed)
            SettingsActionRow(title: Messages.AppInstanceSettingsView.overviewText14.localized, detail: Messages.AppInstanceSettingsView.overviewText15.localized, button: Messages.AppInstanceSettingsView.overviewText16.localized) { updatingModpack = true }
                .disabled(model.busy || (!ModpackUpdateStore.hasPending(paths: model.paths, instanceID: instance.id) && model.isInstanceInUse(instance.id)))
        }
    }
    @ViewBuilder private var files: some View {
        Section(Messages.AppInstanceSettingsView.filesText1.localized) {
            LabeledContent(Messages.AppInstanceSettingsView.filesText2.localized, value: (locationInstance.runDirectory ?? .isolated).title)
            VStack(alignment: .leading, spacing: 6) {
                Text((locationInstance.runDirectory ?? .isolated).explanation).font(.caption).foregroundStyle(.secondary)
                Text(model.paths.game(instance.id).path).font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.customDirectoryErrors[instance.id] { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            LabeledContent(Messages.AppInstanceSettingsView.errorText1.localized) {
                Button(directoryCopyPending ? Messages.AppInstanceSettingsView.errorText2.localized : Messages.AppInstanceSettingsView.errorText3.localized) { changingDirectory = true }
                    .disabled(model.busy || (!directoryCopyPending && model.isInstanceInUse(instance.id)))
            }
            if locationInstance.customRunDirectory != nil {
                Button(locationInstance.runDirectory == .custom ? Messages.AppInstanceSettingsView.errorText4.localized : Messages.AppInstanceSettingsView.errorText5.localized) { relocatingDirectory = true }.disabled(model.busy)
            }
            HStack {
                Button(Messages.AppInstanceSettingsView.errorText6.localized, systemImage: "folder") { model.reveal(locationInstance) }
                Spacer()
                Button(Messages.AppInstanceSettingsView.errorText7.localized) { model.reveal(locationInstance, folder: "mods") }
                Button(Messages.AppInstanceSettingsView.errorText8.localized) { model.reveal(locationInstance, folder: "saves") }
            }
        }
        Section {
            if model.pendingInstanceCopyIDs.contains(instance.id) || InstanceCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.errorText9.localized, detail: Messages.AppInstanceSettingsView.errorText10.localized, button: Messages.AppInstanceSettingsView.errorText11.localized) { copyingInstance = true }.disabled(model.busy)
            } else {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.errorText12.localized, detail: Messages.AppInstanceSettingsView.errorText13.localized, button: Messages.AppInstanceSettingsView.errorText14.localized) { copyingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
            }
            if model.pendingInstanceMoveIDs.contains(instance.id) || InstanceMoveGuard.hasPending(paths: model.paths, instanceID: instance.id) {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.errorText15.localized, detail: Messages.AppInstanceSettingsView.errorText16.localized, button: Messages.AppInstanceSettingsView.errorText11.localized) { movingInstance = true }.disabled(model.busy)
            } else {
                SettingsActionRow(title: Messages.AppInstanceSettingsView.errorText17.localized, detail: Messages.AppInstanceSettingsView.errorText18.localized, button: Messages.AppInstanceSettingsView.errorText19.localized) { movingInstance = true }.disabled(model.busy || model.isInstanceInUse(instance.id))
            }
        } header: { Text(Messages.AppInstanceSettingsView.errorText20.localized) } footer: { Text(Messages.AppInstanceSettingsView.errorText21.localized) }
        if !preservedWorkspaces.isEmpty {
            Section(Messages.AppInstanceSettingsView.errorText22.localized) {
                ForEach(Array(preservedWorkspaces.enumerated()), id: \.offset) { index, url in
                    LabeledContent(Messages.AppInstanceSettingsView.errorText23(String(describing: index + 1)).localized) { Button(Messages.AppInstanceSettingsView.errorText24.localized) { NSWorkspace.shared.open(url) } }
                }
            }
        }
    }
    private func save() {
        guard !instance.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { pane = .overview; settingsIssue = Messages.AppInstanceSettingsView.saveText1.localized; return }
        let effective = launchOverrides.resolve(defaults: model.state.settings.defaultLaunchSettings)
        if let issue = SettingsValidation.issue(in: effective) { pane = .containing(issue.key); settingsIssue = issue.message; return }
        instance.launchOverrides = launchOverrides
        if model.updateSettings(instance, basedOn: original) { dismiss() }
        else { settingsIssue = model.error ?? Messages.AppInstanceSettingsView.issueText1.localized }
    }

    private func chooseIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false; panel.prompt = Messages.AppInstanceSettingsView.panelText1.localized
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadingIcon = true
        Task {
            defer { loadingIcon = false }
            do { instance.iconPNG = try await Task.detached(priority: .userInitiated) { try InstanceIconImage.load(url) }.value }
            catch { settingsIssue = error.localizedDescription }
        }
    }
}
