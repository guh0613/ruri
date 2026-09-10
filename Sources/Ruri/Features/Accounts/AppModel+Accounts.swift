import Foundation
import RuriCore

extension AppModel {
    func addOffline(_ username: String) throws {
        let account = try Account(username: username)
        guard !state.accounts.contains(where: { $0.uuid == account.uuid }) else { throw RuriError.message("这个离线账号已存在。") }
        state.accounts.append(account); state.activeAccountID = account.id; save()
    }
    func addMicrosoft(_ account: Account, credentials: AccountCredentials) throws {
        var account = account
        if let existing = state.accounts.first(where: { $0.kind == .microsoft && $0.uuid == account.uuid }) { account.id = existing.id }
        try CredentialStore.save(credentials, for: account.id)
        state.accounts.removeAll { $0.id == account.id }; state.accounts.append(account); state.activeAccountID = account.id; save()
    }
    func removeAccount(_ account: Account) {
        do {
            if account.kind == .microsoft { try CredentialStore.remove(for: account.id) }
            state.accounts.removeAll { $0.id == account.id }
            if state.activeAccountID == account.id { state.activeAccountID = state.accounts.first?.id }
            save()
        } catch { self.error = error.localizedDescription }
    }
}
