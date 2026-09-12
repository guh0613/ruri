import RuriLocalization
import SwiftUI
import RuriCore

struct ExternalAccountForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let existing: Account?
    @State private var address = ""
    @State private var server: ExternalAuthServer?
    @State private var username = ""
    @State private var password = ""
    @State private var pending: ExternalAuthSession?
    @State private var profileID = ""
    @State private var task: Task<Void, Never>?
    @State private var error: String?

    init(existing: Account? = nil) {
        self.existing = existing
        _server = State(initialValue: existing?.externalLogin?.server)
        _username = State(initialValue: existing?.externalLogin?.username ?? "")
    }
    private var knownServers: [ExternalAuthServer] {
        var seen = Set<URL>()
        return model.state.accounts.compactMap { $0.externalLogin?.server }.filter { seen.insert($0.url).inserted }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let server {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(server.name).font(.headline)
                        Spacer()
                        if existing == nil { Button(Messages.AppExternalAccountForm.changeServer.localized) { self.server = nil; pending = nil; password = "" }.disabled(task != nil) }
                    }
                    Text(server.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let pending {
                    Text(Messages.AppExternalAccountForm.chooseRole.localized).font(.callout)
                    Picker(Messages.AppExternalAccountForm.roleLabel.localized, selection: $profileID) {
                        ForEach(pending.availableProfiles ?? []) { profile in Text(profile.name).tag(profile.id) }
                    }.disabled(task != nil)
                    Button(Messages.AppExternalAccountForm.addRole.localized) { selectProfile(pending, server: server) }
                        .buttonStyle(.borderedProminent).disabled(task != nil || profileID.isEmpty)
                } else {
                    LabeledContent(Messages.AppExternalAccountForm.authServer.localized) { TextField(Messages.AppExternalAccountForm.accountName.localized, text: $username).textFieldStyle(.roundedBorder).disabled(existing != nil || task != nil) }
                    LabeledContent(Messages.AppExternalAccountForm.password.localized) { SecureField(Messages.AppExternalAccountForm.authPassword.localized, text: $password).textFieldStyle(.roundedBorder).disabled(task != nil) }
                    Text(Messages.AppExternalAccountForm.credentialsHelp.localized).font(.caption).foregroundStyle(.secondary)
                    Button(existing == nil ? Messages.AppExternalAccountForm.login.localized : Messages.AppExternalAccountForm.relogin.localized) { login(server) }
                        .buttonStyle(.borderedProminent).disabled(task != nil || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            } else {
                LabeledContent(Messages.AppExternalAccountForm.serverAddress.localized) { TextField("https://…", text: $address).textFieldStyle(.roundedBorder) }
                Text(Messages.AppExternalAccountForm.serverAddressHelp.localized).font(.caption).foregroundStyle(.secondary)
                if !knownServers.isEmpty {
                    Menu(Messages.AppExternalAccountForm.useExistingServer.localized) {
                        ForEach(knownServers, id: \.url) { value in Button(value.name) { address = value.url.absoluteString; discover() } }
                    }.disabled(task != nil)
                }
                Button(Messages.AppExternalAccountForm.identifyServer.localized) { discover() }.buttonStyle(.borderedProminent).disabled(address.isEmpty || task != nil)
            }
            if task != nil { ProgressView(Messages.AppExternalAccountForm.connectingServer.localized).controlSize(.small) }
            if let error { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        }.disabled(model.busy || model.readOnly).onDisappear { task?.cancel(); password = ""; pending = nil }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        error = nil
        task = Task {
            do { try await operation() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            task = nil
        }
    }
    private func discover() {
        let input = address
        run {
            let value = try await ExternalAuthentication().discover(input)
            try Task.checkCancellation(); server = value.server
        }
    }
    private func login(_ server: ExternalAuthServer) {
        let loginName = username.trimmingCharacters(in: .whitespacesAndNewlines), secret = password
        password = ""
        run {
            var result = try await ExternalAuthentication().login(server: server, username: loginName, password: secret)
            try Task.checkCancellation()
            if let existing, result.selectedProfile == nil {
                guard let profile = result.availableProfiles?.first(where: { $0.id.replacingOccurrences(of: "-", with: "").lowercased() == existing.uuid }) else { throw RuriError.message(Messages.AppExternalAccountForm.profileUnavailable) }
                result = try await ExternalAuthentication().select(profile, from: result, server: server)
            }
            if result.selectedProfile != nil { try finish(result, server: server, username: loginName) }
            else { pending = result; profileID = result.availableProfiles?.first?.id ?? "" }
        }
    }
    private func selectProfile(_ pending: ExternalAuthSession, server: ExternalAuthServer) {
        guard let profile = pending.availableProfiles?.first(where: { $0.id == profileID }) else { return }
        run {
            let result = try await ExternalAuthentication().select(profile, from: pending, server: server)
            try finish(result, server: server, username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    private func finish(_ result: ExternalAuthSession, server: ExternalAuthServer, username: String) throws {
        try Task.checkCancellation()
        let account = try result.account(server: server, username: username, replacing: existing)
        try model.addExternal(account, credentials: result.credentials, requireExisting: existing != nil, activate: existing == nil)
        pending = nil; dismiss()
    }
}

struct ExternalAccountReloginView: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionHeading(title: Messages.AppExternalAccountForm.reloginAccount(String(describing: account.username)).localized, subtitle: Messages.AppExternalAccountForm.reloginHelp.localized)
            ExternalAccountForm(existing: account)
            HStack { Spacer(); Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(30).frame(width: 500)
    }
}
