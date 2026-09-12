import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

enum PreferencesPane: String, CaseIterable, Identifiable {
    case general, runtime, launch, advanced, network
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: Messages.AppPreferencesView.general.localized
        case .runtime: InstanceSettingsPane.runtime.title
        case .launch: InstanceSettingsPane.launch.title
        case .advanced: InstanceSettingsPane.advanced.title
        case .network: Messages.AppPreferencesView.networkAndServices.localized
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .runtime: "memorychip"
        case .launch: "macwindow"
        case .advanced: "terminal"
        case .network: "network"
        }
    }
    var launchPane: InstanceSettingsPane? {
        switch self {
        case .runtime: .runtime
        case .launch: .launch
        case .advanced: .advanced
        default: nil
        }
    }
    static func containing(_ key: LaunchSettingKey) -> Self {
        allCases.first { $0.launchPane?.launchKeys.contains(key) == true } ?? .runtime
    }
}

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(LocalizationContext.preferenceKey) private var language = LocalizationContext.systemPreference
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TabView(selection: $model.preferencesPane) {
                ForEach(PreferencesPane.allCases) { pane in
                    Group {
                        if let launchPane = pane.launchPane, let draft = model.defaultLaunchSettingsDraft {
                            DefaultLaunchSettingsView(draft: draft, pane: launchPane)
                        } else if pane == .general {
                            Form { general }.formStyle(.grouped)
                        } else if pane == .network {
                            Form { network }.formStyle(.grouped)
                        }
                    }
                    .tabItem { Label(pane.title, systemImage: pane.symbol) }
                    .tag(pane)
                }
            }.padding(16)
            if let draft = model.defaultLaunchSettingsDraft, draft.hasChanges {
                launchSettingsActions(draft)
            }
        }
        .onAppear { synchronizeLaunchSettings() }
        .onChange(of: model.state.settings.defaultLaunchSettings) { synchronizeLaunchSettings() }
        .onChange(of: model.state.settings.appearance) { model.save() }
        .onChange(of: model.state.settings.isolationPolicy) { model.save() }
        .onChange(of: model.state.settings.concurrentDownloads) { model.save() }
        .onChange(of: model.state.settings.downloadSource) { model.save(); Task { await model.applyNetworkSettings() } }
        .onChange(of: model.state.settings.microsoftClientID) { model.save() }
    }

    @ViewBuilder private var general: some View {
        @Bindable var model = model
        Section {
            Picker(Messages.AppPreferencesView.theme.localized, selection: $model.state.settings.appearance) {
                Text(Messages.Common.followSystem.localized).tag("system")
                Text(Messages.AppPreferencesView.light.localized).tag("light")
                Text(Messages.AppPreferencesView.dark.localized).tag("dark")
            }.disabled(model.readOnly)
            if LocalizationContext.supportedLanguages.count > 1 {
                Picker(Messages.Common.language.localized, selection: $language) {
                    Text(Messages.Common.followSystem.localized).tag(LocalizationContext.systemPreference)
                    ForEach(LocalizationContext.supportedLanguages, id: \.self) { identifier in
                        Text(Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                    }
                }
            }
        } header: {
            Text(Messages.AppPreferencesView.appearance.localized)
        } footer: {
            if LocalizationContext.supportedLanguages.count > 1 { Text(Messages.Common.languageRestart.localized) }
        }
        Section {
            Picker(Messages.AppPreferencesView.newInstanceIsolation.localized, selection: Binding(get: { model.state.settings.isolationPolicy ?? .always }, set: { model.state.settings.isolationPolicy = $0 })) {
                ForEach(GameIsolationPolicy.allCases) { Text($0.title).tag($0) }
            }.disabled(model.readOnly)
        } header: {
            Text(Messages.AppPreferencesView.newInstances.localized)
        } footer: {
            Text(Messages.AppPreferencesView.newInstanceIsolationDetails.localized).fixedSize(horizontal: false, vertical: true)
        }
        Section(Messages.AppPreferencesView.data.localized) {
            HStack {
                Text(Messages.AppPreferencesView.instanceFolders.localized)
                Spacer()
                Button(Messages.AppPreferencesView.manageInstanceFolders.localized, systemImage: "folder.badge.gearshape") { model.showDirectories = true }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(Messages.AppPreferencesView.dataDirectory.localized)
                    Spacer()
                    Button(Messages.AppPreferencesView.showInFinder.localized, systemImage: "folder") {
                        do { try model.paths.prepare(); NSWorkspace.shared.open(model.paths.root) }
                        catch { model.error = error.localizedDescription }
                    }.help(Messages.AppPreferencesView.openDataDirectory.localized)
                }
                Text(model.paths.root.path).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.multilineTextAlignment(.leading).padding(.vertical, 3)
        }
        Section {
            LabeledContent(Messages.AppPreferencesView.version.localized, value: BuildConfiguration().version)
        } header: {
            Text(Messages.AppPreferencesView.aboutRuri.localized)
        } footer: {
            Text(Messages.AppPreferencesView.aboutRuriDescription.localized).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var network: some View {
        @Bindable var model = model
        Section {
            Picker(Messages.AppPreferencesView.downloadSource.localized, selection: Binding(get: { model.state.settings.downloadSource ?? .automatic }, set: { model.state.settings.downloadSource = $0 })) {
                ForEach(DownloadSource.allCases) { Text($0.title).tag($0) }
            }.disabled(model.readOnly)
            Stepper(value: $model.state.settings.concurrentDownloads, in: 1...16) {
                HStack {
                    Text(Messages.AppPreferencesView.parallelDownloadsLabel.localized)
                    Spacer()
                    Text(model.state.settings.concurrentDownloads, format: .number).monospacedDigit()
                }
            }.disabled(model.readOnly)
        } header: {
            Text(Messages.AppPreferencesView.downloadsAndNetwork.localized)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Messages.AppPreferencesView.automaticMirrorDetails.localized)
                Link(Messages.AppPreferencesView.bmclapiMirror.localized, destination: AppLinks.bmclapiDocumentation)
            }.fixedSize(horizontal: false, vertical: true)
        }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(Messages.AppPreferencesView.customClientID.localized)
                TextField(Messages.AppPreferencesView.customClientID.localized, text: $model.state.settings.microsoftClientID,
                          prompt: Text(BuildConfiguration().microsoftClientID.isEmpty ? Messages.AppPreferencesView.enterClientID.localized : Messages.AppPreferencesView.useBuiltInClientID.localized))
                    .labelsHidden().textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.leading).autocorrectionDisabled().disabled(model.readOnly)
                    .accessibilityLabel(Messages.AppPreferencesView.customClientID.localized)
            }.padding(.vertical, 3)
        } header: {
            Text(Messages.AppPreferencesView.microsoftLogin.localized)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !BuildConfiguration().microsoftClientID.isEmpty { Text(Messages.AppPreferencesView.microsoftLoginDetails.localized) }
                Text(Messages.AppPreferencesView.customClientIDDetails.localized)
                Link(Messages.AppPreferencesView.microsoftRegistrationDocs.localized, destination: AppLinks.microsoftRegistration)
            }.fixedSize(horizontal: false, vertical: true)
        }
        CurseForgeSettingsSection()
    }

    private func launchSettingsActions(_ draft: DefaultLaunchSettingsDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            if let issue = draft.issue {
                Label(issue, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }
            HStack(spacing: 12) {
                Text(Messages.AppPreferencesView.unsavedGameSettings.localized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.AppPreferencesView.discardGameChanges.localized) { draft.reset(to: model.state.settings.defaultLaunchSettings) }
                Button(Messages.AppDefaultLaunchSettingsView.saveDefaultSettings.localized) { saveLaunchSettings(draft) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s").disabled(model.readOnly)
            }.padding(.horizontal, 20).padding(.bottom, 14)
        }
    }
    private func synchronizeLaunchSettings() {
        if let draft = model.defaultLaunchSettingsDraft { draft.synchronize(with: model.state.settings.defaultLaunchSettings) }
        else { model.defaultLaunchSettingsDraft = .init(values: model.state.settings.defaultLaunchSettings) }
    }
    private func saveLaunchSettings(_ draft: DefaultLaunchSettingsDraft) {
        let values = draft.values
        if let failure = SettingsValidation.issue(in: values) {
            model.preferencesPane = .containing(failure.key)
            draft.issue = failure.message
            return
        }
        if model.updateDefaultLaunchSettings(values, basedOn: draft.original) { draft.reset(to: model.state.settings.defaultLaunchSettings) }
        else { draft.issue = model.error ?? Messages.AppDefaultLaunchSettingsView.saveDefaultFailure.localized }
    }
}
