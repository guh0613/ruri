import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct AddAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "microsoft"
    @State private var username = ""
    @State private var code: DeviceCode?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(title: Messages.AppAddAccountView.addAccount.localized)
            Picker(Messages.AppAddAccountView.accountType.localized, selection: $mode) { Text("Microsoft").tag("microsoft"); Text(Messages.AppAddAccountView.externalAuth.localized).tag("external"); Text(Messages.AppAddAccountView.offlineAccount.localized).tag("offline") }.pickerStyle(.segmented).disabled(task != nil)
            if mode == "external" {
                ExternalAccountForm()
            } else if mode == "offline" {
                TextField(Messages.AppAddAccountView.playerName.localized, text: $username).textFieldStyle(.roundedBorder)
                Text(Messages.AppAddAccountView.playerNameHelp.localized).font(.callout).foregroundStyle(.secondary)
            } else if model.state.settings.effectiveMicrosoftClientID.isEmpty {
                Label(Messages.AppAddAccountView.configureMicrosoft.localized, systemImage: "key.horizontal").font(.headline)
                Text(Messages.AppAddAccountView.microsoftHelp.localized).font(.callout).foregroundStyle(.secondary)
                Button(Messages.AppAddAccountView.openSettings.localized) { model.page = .settings; dismiss() }
            } else if let code {
                Text(Messages.AppAddAccountView.enterMicrosoftCode.localized).foregroundStyle(.secondary)
                HStack { Text(code.user_code).font(.system(size: 31, weight: .bold, design: .monospaced)).textSelection(.enabled); Spacer(); Button(Messages.AppAddAccountView.copyCode.localized) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.user_code, forType: .string) } }
                Button(Messages.AppAddAccountView.openMicrosoftLogin.localized, systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(code.verification_uri) }
                HStack { ProgressView().controlSize(.small); Text(Messages.AppAddAccountView.waitingMicrosoftLogin.localized).font(.callout).foregroundStyle(.secondary) }
            } else {
                Label(Messages.AppAddAccountView.minecraftOwnership.localized, systemImage: "person.badge.key").font(.callout).foregroundStyle(.secondary)
                if task != nil { ProgressView(Messages.AppAddAccountView.requestLoginCode.localized) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer(); Button(Messages.Common.cancel.localized) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                if mode == "offline" {
                    Button(Messages.AppAddAccountView.addAccountAction.localized) { do { try model.addOffline(username); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(username.isEmpty)
                } else if mode == "microsoft", code == nil {
                    Button(Messages.AppAddAccountView.continueLogin.localized) { login() }.buttonStyle(.borderedProminent).disabled(task != nil || model.state.settings.effectiveMicrosoftClientID.isEmpty)
                }
            }
        }.padding(30).frame(width: 500).onDisappear { task?.cancel() }
    }
    private func login() {
        error = nil
        task = Task {
            do {
                let auth = MicrosoftAuth(clientID: model.state.settings.effectiveMicrosoftClientID)
                let code = try await auth.begin(); self.code = code
                NSWorkspace.shared.open(code.verification_uri)
                let (account, credentials) = try await auth.finish(code)
                try Task.checkCancellation(); try model.addMicrosoft(account, credentials: credentials); dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; code = nil } }
            task = nil
        }
    }
}
