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
                Section(Messages.AppPreferencesView.modelText1.localized) {
                    Picker(Messages.AppPreferencesView.modelText2.localized, selection: $model.state.settings.appearance) { Text(Messages.Common.followSystem.localized).tag("system"); Text(Messages.AppPreferencesView.modelText3.localized).tag("light"); Text(Messages.AppPreferencesView.modelText4.localized).tag("dark") }
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
                Section(Messages.AppPreferencesView.modelText5.localized) {
                    LabeledContent(Messages.AppPreferencesView.modelText6.localized, value: model.state.settings.defaultLaunchSettings.memory.mode == .automatic ? Messages.AppPreferencesView.modelText7.localized : "\(model.state.settings.defaultMemoryMB) MB")
                    Button(Messages.AppPreferencesView.modelText8.localized, systemImage: "slider.horizontal.3") { showLaunchDefaults = true }
                    Text(Messages.AppPreferencesView.modelText9.localized).font(.caption).foregroundStyle(.secondary)
                    Picker(Messages.AppPreferencesView.modelText10.localized, selection: Binding(get: { model.state.settings.isolationPolicy ?? .always }, set: { model.state.settings.isolationPolicy = $0 })) {
                        ForEach(GameIsolationPolicy.allCases) { Text($0.title).tag($0) }
                    }
                    Text(Messages.AppPreferencesView.modelText11.localized).font(.caption).foregroundStyle(.secondary)
                }
                Section(Messages.AppPreferencesView.modelText12.localized) {
                    Picker(Messages.AppPreferencesView.modelText13.localized, selection: Binding(get: { model.state.settings.downloadSource ?? .automatic }, set: { model.state.settings.downloadSource = $0 })) {
                        ForEach(DownloadSource.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper(Messages.AppPreferencesView.modelText14(String(describing: model.state.settings.concurrentDownloads)).localized, value: $model.state.settings.concurrentDownloads, in: 1...16)
                    Text(Messages.AppPreferencesView.modelText15.localized).font(.caption).foregroundStyle(.secondary)
                    Link(Messages.AppPreferencesView.modelText16.localized, destination: AppLinks.bmclapiDocumentation)
                }
                Section(Messages.AppPreferencesView.modelText17.localized) {
                    if !BuildConfiguration().microsoftClientID.isEmpty {
                        Text(Messages.AppPreferencesView.modelText18.localized).font(.caption).foregroundStyle(.secondary)
                    }
                    TextField(Messages.AppPreferencesView.modelText19.localized, text: $model.state.settings.microsoftClientID).font(.system(.body, design: .monospaced))
                    Text(Messages.AppPreferencesView.modelText20.localized).font(.caption).foregroundStyle(.secondary)
                    Link(Messages.AppPreferencesView.modelText21.localized, destination: AppLinks.microsoftRegistration)
                }
                CurseForgeSettingsSection()
                Section(Messages.AppPreferencesView.modelText22.localized) {
                    Button(Messages.AppPreferencesView.modelText23.localized, systemImage: "folder.badge.gearshape") { model.showDirectories = true }
                    LabeledContent(Messages.AppPreferencesView.modelText24.localized) { Text(model.paths.root.path).font(.caption).textSelection(.enabled) }
                    Button(Messages.AppPreferencesView.modelText25.localized, systemImage: "folder") { do { try model.paths.prepare(); NSWorkspace.shared.open(model.paths.root) } catch { model.error = error.localizedDescription } }
                }
                Section(Messages.AppPreferencesView.modelText26.localized) {
                    LabeledContent(Messages.AppPreferencesView.modelText27.localized, value: BuildConfiguration().version)
                    Text(Messages.AppPreferencesView.modelText28.localized).font(.caption).foregroundStyle(.secondary)
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
