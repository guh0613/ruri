import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct PreferencesView: View {
    @Environment(AppModel.self) private var model
    @State private var showLaunchDefaults = false
    @AppStorage(LocalizationContext.preferenceKey) private var language = LocalizationContext.systemPreference
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section(Messages.AppPreferencesView.appearance.localized) {
                    Picker(Messages.AppPreferencesView.theme.localized, selection: $model.state.settings.appearance) { Text(Messages.Common.followSystem.localized).tag("system"); Text(Messages.AppPreferencesView.light.localized).tag("light"); Text(Messages.AppPreferencesView.dark.localized).tag("dark") }
                    if LocalizationContext.supportedLanguages.count > 1 {
                        Picker(Messages.Common.language.localized, selection: $language) {
                            Text(Messages.Common.followSystem.localized).tag(LocalizationContext.systemPreference)
                            ForEach(LocalizationContext.supportedLanguages, id: \.self) { identifier in
                                Text(Locale(identifier: identifier).localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                            }
                        }
                        Text(Messages.Common.languageRestart.localized).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(Messages.AppPreferencesView.systemDefault.localized) {
                    LabeledContent(Messages.AppPreferencesView.defaultMemory.localized, value: model.state.settings.defaultLaunchSettings.memory.mode == .automatic ? Messages.AppPreferencesView.automaticEstimate.localized : "\(model.state.settings.defaultMemoryMB) MB")
                    Button(Messages.AppPreferencesView.editDefaultLaunchSettings.localized, systemImage: "slider.horizontal.3") { showLaunchDefaults = true }
                    Text(Messages.AppPreferencesView.inheritedLaunchSettingsDetails.localized).font(.caption).foregroundStyle(.secondary)
                    Picker(Messages.AppPreferencesView.newInstanceIsolation.localized, selection: Binding(get: { model.state.settings.isolationPolicy ?? .always }, set: { model.state.settings.isolationPolicy = $0 })) {
                        ForEach(GameIsolationPolicy.allCases) { Text($0.title).tag($0) }
                    }
                    Text(Messages.AppPreferencesView.newInstanceIsolationDetails.localized).font(.caption).foregroundStyle(.secondary)
                }
                Section(Messages.AppPreferencesView.downloadsAndNetwork.localized) {
                    Picker(Messages.AppPreferencesView.downloadSource.localized, selection: Binding(get: { model.state.settings.downloadSource ?? .automatic }, set: { model.state.settings.downloadSource = $0 })) {
                        ForEach(DownloadSource.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(Messages.AppPreferencesView.parallelDownloads(String(describing: model.state.settings.concurrentDownloads)).localized, value: $model.state.settings.concurrentDownloads, in: 1...16)
                    Text(Messages.AppPreferencesView.automaticMirrorDetails.localized).font(.caption).foregroundStyle(.secondary)
                    Link(Messages.AppPreferencesView.bmclapiMirror.localized, destination: AppLinks.bmclapiDocumentation)
                }
                Section(Messages.AppPreferencesView.microsoftLogin.localized) {
                    if !BuildConfiguration().microsoftClientID.isEmpty {
                        Text(Messages.AppPreferencesView.microsoftLoginDetails.localized).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField(Messages.AppPreferencesView.customClientID.localized, text: $model.state.settings.microsoftClientID).font(.system(.body, design: .monospaced))
                    Text(Messages.AppPreferencesView.customClientIDDetails.localized).font(.caption).foregroundStyle(.secondary)
                    Link(Messages.AppPreferencesView.microsoftRegistrationDocs.localized, destination: AppLinks.microsoftRegistration)
                }
                CurseForgeSettingsSection()
                Section(Messages.AppPreferencesView.data.localized) {
                    Button(Messages.AppPreferencesView.manageInstanceFolders.localized, systemImage: "folder.badge.gearshape") { model.showDirectories = true }
                    LabeledContent(Messages.AppPreferencesView.dataDirectory.localized) { Text(model.paths.root.path).font(.caption).textSelection(.enabled) }
                    Button(Messages.AppPreferencesView.openDataDirectory.localized, systemImage: "folder") { do { try model.paths.prepare(); NSWorkspace.shared.open(model.paths.root) } catch { model.error = error.localizedDescription } }
                }
                Section(Messages.AppPreferencesView.aboutRuri.localized) {
                    LabeledContent(Messages.AppPreferencesView.version.localized, value: BuildConfiguration().version)
                    Text(Messages.AppPreferencesView.aboutRuriDescription.localized).font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
        .onChange(of: model.state.settings.appearance) { model.save() }
        .sheet(isPresented: $showLaunchDefaults) { DefaultLaunchSettingsView(settings: model.state.settings) }
        .onChange(of: model.state.settings.isolationPolicy) { model.save() }
        .onChange(of: model.state.settings.concurrentDownloads) { model.save() }
        .onChange(of: model.state.settings.downloadSource) { model.save(); Task { await model.applyNetworkSettings() } }
        .onChange(of: model.state.settings.microsoftClientID) { model.save() }
    }
}
