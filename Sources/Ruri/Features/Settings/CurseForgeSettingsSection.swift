import RuriLocalization
import SwiftUI
import RuriCore

struct CurseForgeSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var configuringKey = false
    @State private var hasCustomKey = CurseForgeKeyStore.hasCustomKey()
    var body: some View {
        Section {
            HStack(spacing: 12) {
                Text("API Key")
                Spacer()
                Text(hasCustomKey ? Messages.AppCurseForgeSettingsSection.keychainSaved.localized : model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.bundledKey.localized : Messages.AppCurseForgeSettingsSection.notConfigured.localized)
                    .foregroundStyle(.secondary)
                Button(hasCustomKey ? Messages.AppCurseForgeSettingsSection.changeApiKey.localized : Messages.AppCurseForgeSettingsSection.configureApiKey.localized) {
                    configuringKey = true
                }.fixedSize().disabled(model.readOnly)
            }
        } header: {
            Text("CurseForge")
        } footer: {
            Text(Messages.AppCurseForgeSettingsSection.apiKeyUsage.localized).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $configuringKey, onDismiss: { hasCustomKey = CurseForgeKeyStore.hasCustomKey() }) { CurseForgeAPIKeyView() }
    }
}

struct CurseForgeAPIKeyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    private let hasCustomKey = CurseForgeKeyStore.hasCustomKey()
    @State private var error: String?
    @FocusState private var keyIsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(Messages.AppCurseForgeSettingsSection.apiKeySettings.localized).font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                SecureField("API Key", text: $key, prompt: Text(hasCustomKey ? Messages.AppCurseForgeSettingsSection.replaceApiKey.localized : Messages.AppCurseForgeSettingsSection.enterApiKey.localized))
                    .textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                    .focused($keyIsFocused).accessibilityLabel("API Key").disabled(model.readOnly)
                Text(Messages.AppCurseForgeSettingsSection.apiKeyStorageHelp.localized)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if CurseForgeKeyStore.hasBundledKey {
                    Text(Messages.AppCurseForgeSettingsSection.bundledKeyHelp.localized)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Link(Messages.AppCurseForgeSettingsSection.apiApplicationGuide.localized, destination: AppLinks.curseForgeAPI)
                    .font(.callout)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if hasCustomKey {
                    Button(Messages.AppCurseForgeSettingsSection.removeApiKey.localized, role: .destructive, action: remove)
                        .disabled(model.readOnly)
                }
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppCurseForgeSettingsSection.saveToKeychain.localized, action: save)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.readOnly)
            }
        }.padding(24).frame(width: 480)
        .interactiveDismissDisabled(!key.isEmpty)
        .onAppear { keyIsFocused = true }
        .onChange(of: key) { error = nil }
    }

    private func save() {
        guard !model.readOnly else { return }
        do {
            try CurseForgeKeyStore.save(key)
            model.curseForgeConfigured = true
            key = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func remove() {
        guard !model.readOnly else { return }
        do {
            try CurseForgeKeyStore.remove()
            model.curseForgeConfigured = CurseForgeKeyStore.isConfigured()
            key = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
