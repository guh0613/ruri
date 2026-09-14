import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct AddAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var existing: Account? = nil
    @State private var mode = "microsoft"
    @State private var username = ""
    @State private var clientID = ""
    @State private var code: DeviceCode?
    @State private var task: Task<Void, Never>?
    @State private var error: String?
    @FocusState private var usernameFocused: Bool
    private var validOfflineName: Bool { (try? Account(username: username.trimmingCharacters(in: .whitespacesAndNewlines))) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(existing == nil ? Messages.AppAddAccountView.addAccount.localized : Messages.AccountCenter.reloginTitle.localized)
                    .font(.title2.weight(.semibold))
                Text(existing.map { Messages.AccountCenter.reloginHelp($0.username).localized } ?? Messages.AccountCenter.addAccountHelp.localized)
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            VStack(alignment: .leading, spacing: 20) {
                if existing == nil {
                    Picker(Messages.AppAddAccountView.accountType.localized, selection: $mode) {
                        Text("Microsoft").tag("microsoft")
                        Text(Messages.AppAddAccountView.externalAuth.localized).tag("external")
                        Text(Messages.AppAddAccountView.offlineAccount.localized).tag("offline")
                    }.pickerStyle(.segmented).disabled(task != nil)
                }
                Group {
                    if mode == "external" { ExternalAccountForm() }
                    else if mode == "offline" { offlineForm }
                    else { microsoftForm }
                }.frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).textSelection(.enabled)
                }
            }.padding(24)
            Divider()
            HStack {
                if task != nil { ProgressView().controlSize(.small) }
                Spacer()
                Button(Messages.Common.cancel.localized) { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                if mode == "offline" {
                    Button(Messages.AppAddAccountView.addAccountAction.localized) {
                        do { try model.addOffline(username); dismiss() } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!validOfflineName || model.readOnly)
                } else if mode == "microsoft", code == nil {
                    Button(Messages.AppAddAccountView.continueLogin.localized) { login() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(task != nil || clientID.isEmpty || model.readOnly)
                }
            }.padding(20)
        }.frame(width: 520)
        .onAppear {
            clientID = existing.flatMap { try? CredentialStore.load(for: $0.id).clientID } ?? model.state.settings.effectiveMicrosoftClientID
        }
        .onChange(of: mode) { error = nil; usernameFocused = mode == "offline" }
        .onDisappear { task?.cancel() }
    }
    private var offlineForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(Messages.AppAddAccountView.offlineAccount.localized, systemImage: "desktopcomputer").font(.headline)
            TextField(Messages.AppAddAccountView.playerName.localized, text: $username)
                .textFieldStyle(.roundedBorder).focused($usernameFocused)
            Text(Messages.AppAddAccountView.playerNameHelp.localized).font(.callout).foregroundStyle(.secondary)
            Text(Messages.AccountCenter.offlineLoginHelp.localized).font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var microsoftForm: some View {
        if clientID.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Label(Messages.AppAddAccountView.configureMicrosoft.localized, systemImage: "key.horizontal").font(.headline)
                Text(Messages.AppAddAccountView.microsoftHelp.localized).font(.callout).foregroundStyle(.secondary)
                Button(Messages.AppAddAccountView.openSettings.localized) { model.page = .settings; dismiss() }
            }
        } else if let code {
            VStack(alignment: .leading, spacing: 16) {
                Text(Messages.AppAddAccountView.enterMicrosoftCode.localized).foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Text(code.user_code).font(.system(size: 32, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(Messages.AppAddAccountView.copyCode.localized) {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code.user_code, forType: .string)
                    }
                }.padding(16).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                Button(Messages.AppAddAccountView.openMicrosoftLogin.localized, systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(code.verification_uri) }
                Text(Messages.AppAddAccountView.waitingMicrosoftLogin.localized).font(.callout).foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Label(Messages.AccountCenter.microsoftLogin.localized, systemImage: "person.badge.key").font(.headline)
                Text(Messages.AppAddAccountView.minecraftOwnership.localized).font(.callout).foregroundStyle(.secondary)
                Text(Messages.AccountCenter.browserLoginHelp.localized).font(.callout).foregroundStyle(.secondary)
                if task != nil { Text(Messages.AppAddAccountView.requestLoginCode.localized).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private func login() {
        guard task == nil else { return }
        error = nil
        task = Task {
            defer { task = nil }
            do {
                let auth = MicrosoftAuth(clientID: clientID)
                let code = try await auth.begin(); try Task.checkCancellation(); self.code = code
                NSWorkspace.shared.open(code.verification_uri)
                var (account, credentials) = try await auth.finish(code)
                try Task.checkCancellation()
                if let existing { account = try existing.reauthenticated(with: account) }
                let key = existing?.id ?? model.state.accounts.first(where: { $0.hasSameIdentity(as: account) })?.id ?? account.id
                try await model.accountOperations.withLock(for: key) {
                    try model.addMicrosoft(account, credentials: credentials, activate: existing == nil, requireExisting: existing != nil)
                }
                dismiss()
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; code = nil } }
        }
    }
}
