import Foundation
import RuriCore

extension AppModel {
    func addOffline(_ username: String) throws {
        let account = try Account(username: username)
        guard !state.accounts.contains(where: { $0.kind == .offline && $0.uuid == account.uuid }) else { throw RuriError.message("这个离线账号已存在。") }
        state.accounts.append(account); state.activeAccountID = account.id; save()
    }
    func addMicrosoft(_ account: Account, credentials: AccountCredentials) throws {
        var account = account
        if let existing = state.accounts.first(where: { $0.kind == .microsoft && $0.uuid == account.uuid }) { account.id = existing.id }
        try CredentialStore.save(credentials, for: account.id)
        state.accounts.removeAll { $0.id == account.id }; state.accounts.append(account); state.activeAccountID = account.id; save()
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
        guard !readOnly else { throw RuriError.message("当前窗口已暂停写入，请重新打开 Ruri。") }
        guard !requireExisting || state.accounts.contains(where: { $0.id == input.id }) else { throw RuriError.message("此账号已被移除。") }
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
        notice = "已刷新 \(updated.username) 的登录状态。"
    }
    func logoutExternal(_ account: Account) async throws {
        guard let server = account.externalLogin?.server else { return }
        try await ExternalAuthentication().invalidate(server: server, credentials: CredentialStore.loadExternal(for: account.id))
        try Task.checkCancellation()
        removeAccount(account)
    }
}
