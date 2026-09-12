import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func addOffline(_ username: String) throws {
        let account = try Account(username: username)
        guard !state.accounts.contains(where: { $0.kind == .offline && $0.uuid == account.uuid }) else { throw RuriError.message(Messages.AppAppModelAccounts.offlineAccountExists) }
        state.accounts.append(account); state.activeAccountID = account.id; save()
    }
    func addMicrosoft(_ account: Account, credentials: AccountCredentials, activate: Bool = true, requireExisting: Bool = false) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        guard !requireExisting || state.accounts.contains(where: { $0.id == account.id && $0.uuid == account.uuid }) else { throw RuriError.message(Messages.AppAppModelAccounts.accountChanged) }
        var account = account
        if let existing = state.accounts.first(where: { $0.kind == .microsoft && $0.uuid == account.uuid }) { account.id = existing.id }
        try CredentialStore.save(credentials, for: account.id)
        state.accounts.removeAll { $0.id == account.id }; state.accounts.append(account)
        if activate { state.activeAccountID = account.id }
        save()
        if readOnly { throw RuriError.message(Messages.AppAppModelAccounts.accountSaveFailed) }
    }
    func removeAccount(_ account: Account) {
        guard !readOnly else { return }
        do {
            if account.kind == .microsoft { try CredentialStore.remove(for: account.id) }
            if account.kind == .external { try CredentialStore.removeExternal(for: account.id) }
            state.accounts.removeAll { $0.id == account.id }
            if state.activeAccountID == account.id { state.activeAccountID = state.accounts.first?.id }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func addExternal(_ input: Account, credentials: ExternalAccountCredentials, requireExisting: Bool = false, activate: Bool = true) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        guard !requireExisting || state.accounts.contains(where: { $0.id == input.id }) else { throw RuriError.message(Messages.AppAppModelAccounts.externalAccountRemoved) }
        var account = input
        let existing = state.accounts.first { $0.kind == .external && $0.uuid == input.uuid && $0.externalLogin?.server.url == input.externalLogin?.server.url && $0.externalLogin?.username == input.externalLogin?.username }
        if let existing { account.id = existing.id }
        try CredentialStore.saveExternal(credentials, for: account.id)
        var next = state
        next.accounts.removeAll { $0.id == account.id }; next.accounts.append(account)
        if activate { next.activeAccountID = account.id }
        do { acceptState(try StateStore.save(next, to: paths, basedOn: persistedState)) }
        catch { if existing == nil { try? CredentialStore.removeExternal(for: account.id) }; throw error }
    }
    func refreshExternal(_ account: Account) async throws {
        let credentials = try CredentialStore.loadExternal(for: account.id)
        let (updated, refreshed) = try await ExternalAuthentication().refresh(account: account, credentials: credentials, force: true)
        try Task.checkCancellation()
        try addExternal(updated, credentials: refreshed, requireExisting: true, activate: false)
        notice = Messages.AppAppModelAccounts.credentialsRefreshed(String(describing: updated.username)).localized
    }
    func logoutExternal(_ account: Account) async throws {
        guard let server = account.externalLogin?.server else { return }
        try await ExternalAuthentication().invalidate(server: server, credentials: CredentialStore.loadExternal(for: account.id))
        try Task.checkCancellation()
        removeAccount(account)
    }
    func appearanceClient(for requested: Account) async throws -> AccountAppearanceClient {
        guard !readOnly, var account = state.accounts.first(where: { $0.id == requested.id }),
              account.uuid == requested.uuid, account.kind == requested.kind, account.externalLogin == requested.externalLogin else {
            throw RuriError.message(Messages.AppAppModelAccounts.appearanceAccountChanged)
        }
        switch account.kind {
        case .offline: throw RuriError.message(Messages.AppAppModelAccounts.offlineAppearanceUnavailable)
        case .microsoft:
            var credentials = try CredentialStore.load(for: account.id)
            if credentials.expiresAt < Date().addingTimeInterval(120) {
                (account, credentials) = try await MicrosoftAuth(clientID: credentials.clientID).refresh(credentials, account: account)
                try addMicrosoft(account, credentials: credentials, activate: false, requireExisting: true)
            }
            return AccountAppearanceClient(account: account, accessToken: credentials.accessToken)
        case .external:
            let credentials = try CredentialStore.loadExternal(for: account.id)
            let (updated, refreshed) = try await ExternalAuthentication().refresh(account: account, credentials: credentials)
            try addExternal(updated, credentials: refreshed, requireExisting: true, activate: false)
            return AccountAppearanceClient(account: updated, accessToken: refreshed.accessToken)
        }
    }
}
