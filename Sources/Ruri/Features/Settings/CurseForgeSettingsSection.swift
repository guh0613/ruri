import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CurseForgeSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        Section("CurseForge") {
            LabeledContent("API Key", value: model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.keychainSaved.localized : Messages.AppCurseForgeSettingsSection.notConfigured.localized)
            SecureField(model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.replaceApiKey.localized : Messages.AppCurseForgeSettingsSection.enterApiKey.localized, text: $key)
            HStack {
                Button(Messages.AppCurseForgeSettingsSection.saveToKeychain.localized) {
                    do { try CurseForgeKeyStore.save(key); key = ""; error = nil; model.curseForgeConfigured = true }
                    catch { self.error = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.curseForgeConfigured {
                    Button(Messages.AppCurseForgeSettingsSection.removeApiKey.localized) {
                        do { try CurseForgeKeyStore.remove(); key = ""; error = nil; model.curseForgeConfigured = false }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text(Messages.AppCurseForgeSettingsSection.apiKeyUsage.localized).font(.caption).foregroundStyle(.secondary)
            Link(Messages.AppCurseForgeSettingsSection.apiApplicationGuide.localized, destination: AppLinks.curseForgeAPI)
        }
    }
}

/// Local files are copied into the resumable cache after verification, so a
/// dismissed file panel never leaves a security-scoped URL in a future task.
