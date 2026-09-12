import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CurseForgeSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("API Key")
                    Spacer()
                    Text(model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.keychainSaved.localized : Messages.AppCurseForgeSettingsSection.notConfigured.localized)
                        .font(.caption).foregroundStyle(.secondary)
                    if model.curseForgeConfigured {
                        Button(Messages.AppCurseForgeSettingsSection.removeApiKey.localized) {
                            do { try CurseForgeKeyStore.remove(); key = ""; error = nil; model.curseForgeConfigured = false }
                            catch { self.error = error.localizedDescription }
                        }.buttonStyle(.borderless).font(.caption).disabled(model.readOnly)
                    }
                }
                HStack(spacing: 12) {
                    SecureField(model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.replaceApiKey.localized : Messages.AppCurseForgeSettingsSection.enterApiKey.localized, text: $key)
                        .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(.leading)
                        .accessibilityLabel("API Key")
                    Button(Messages.AppCurseForgeSettingsSection.saveToKeychain.localized) {
                        do { try CurseForgeKeyStore.save(key); key = ""; error = nil; model.curseForgeConfigured = true }
                        catch { self.error = error.localizedDescription }
                    }.fixedSize().disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.disabled(model.readOnly)
                if let error { Text(error).foregroundStyle(.red).font(.caption).fixedSize(horizontal: false, vertical: true) }
            }.padding(.vertical, 3)
        } header: {
            Text("CurseForge")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(Messages.AppCurseForgeSettingsSection.apiKeyUsage.localized)
                Link(Messages.AppCurseForgeSettingsSection.apiApplicationGuide.localized, destination: AppLinks.curseForgeAPI)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: key) { error = nil }
    }
}
