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
            LabeledContent("API Key", value: model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.bodyText1.localized : Messages.AppCurseForgeSettingsSection.bodyText2.localized)
            SecureField(model.curseForgeConfigured ? Messages.AppCurseForgeSettingsSection.bodyText3.localized : Messages.AppCurseForgeSettingsSection.bodyText4.localized, text: $key)
            HStack {
                Button(Messages.AppCurseForgeSettingsSection.bodyText5.localized) {
                    do { try CurseForgeKeyStore.save(key); key = ""; error = nil; model.curseForgeConfigured = true }
                    catch { self.error = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.curseForgeConfigured {
                    Button(Messages.AppCurseForgeSettingsSection.bodyText6.localized) {
                        do { try CurseForgeKeyStore.remove(); key = ""; error = nil; model.curseForgeConfigured = false }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text(Messages.AppCurseForgeSettingsSection.errorText1.localized).font(.caption).foregroundStyle(.secondary)
            Link(Messages.AppCurseForgeSettingsSection.errorText2.localized, destination: AppLinks.curseForgeAPI)
        }
    }
}

/// Local files are copied into the resumable cache after verification, so a
/// dismissed file panel never leaves a security-scoped URL in a future task.
