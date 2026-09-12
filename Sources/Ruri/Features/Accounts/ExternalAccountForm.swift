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
                        if existing == nil { Button(Messages.AppExternalAccountForm.serverText1.localized) { self.server = nil; pending = nil; password = "" }.disabled(task != nil) }
                    }
                    Text(server.url.absoluteString).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                if let pending {
                    Text(Messages.AppExternalAccountForm.pendingText1.localized).font(.callout)
                    Picker(Messages.AppExternalAccountForm.pendingText2.localized, selection: $profileID) {
                        ForEach(pending.availableProfiles ?? []) { profile in Text(profile.name).tag(profile.id) }
                    }.disabled(task != nil)
                    Button(Messages.AppExternalAccountForm.pendingText3.localized) { selectProfile(pending, server: server) }
                        .buttonStyle(.borderedProminent).disabled(task != nil || profileID.isEmpty)
                } else {
                    LabeledContent(Messages.AppExternalAccountForm.pendingText4.localized) { TextField(Messages.AppExternalAccountForm.pendingText5.localized, text: $username).textFieldStyle(.roundedBorder).disabled(existing != nil || task != nil) }
                    LabeledContent(Messages.AppExternalAccountForm.pendingText6.localized) { SecureField(Messages.AppExternalAccountForm.pendingText7.localized, text: $password).textFieldStyle(.roundedBorder).disabled(task != nil) }
                    Text(Messages.AppExternalAccountForm.pendingText8.localized).font(.caption).foregroundStyle(.secondary)
                    Button(existing == nil ? Messages.AppExternalAccountForm.pendingText9.localized : Messages.AppExternalAccountForm.pendingText10.localized) { login(server) }
                        .buttonStyle(.borderedProminent).disabled(task != nil || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            } else {
                LabeledContent(Messages.AppExternalAccountForm.pendingText11.localized) { TextField("https://…", text: $address).textFieldStyle(.roundedBorder) }
                Text(Messages.AppExternalAccountForm.pendingText12.localized).font(.caption).foregroundStyle(.secondary)
                if !knownServers.isEmpty {
                    Menu(Messages.AppExternalAccountForm.pendingText13.localized) {
                        ForEach(knownServers, id: \.url) { value in Button(value.name) { address = value.url.absoluteString; discover() } }
                    }.disabled(task != nil)
                }
                Button(Messages.AppExternalAccountForm.pendingText14.localized) { discover() }.buttonStyle(.borderedProminent).disabled(address.isEmpty || task != nil)
            }
            if task != nil { ProgressView(Messages.AppExternalAccountForm.pendingText15.localized).controlSize(.small) }
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
                guard let profile = result.availableProfiles?.first(where: { $0.id.replacingOccurrences(of: "-", with: "").lowercased() == existing.uuid }) else { throw RuriError.message(Messages.AppExternalAccountForm.profileText1) }
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
            SectionHeading(title: Messages.AppExternalAccountForm.bodyText1(String(describing: account.username)).localized, subtitle: Messages.AppExternalAccountForm.bodyText2.localized)
            ExternalAccountForm(existing: account)
            HStack { Spacer(); Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(30).frame(width: 500)
    }
}
