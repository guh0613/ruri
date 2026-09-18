import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func activateAccount(_ account: Account) {
        guard !readOnly, state.accounts.contains(where: { $0.id == account.id }) else { return }
        state.activeAccountID = account.id; save()
    }
    func loadAccountPreview(_ account: Account) {
        guard loadedAccountPreviews.insert(account.id).inserted else { return }
        accountSkins[account.id] = try? SkinLibrary(paths: paths).preview(for: account.id)
        accountCapes[account.id] = try? SkinLibrary(paths: paths).cape(for: account.id)
    }
    func cachedAccountAppearance(_ account: Account) -> AccountAppearance? {
        guard state.accounts.contains(where: { $0.id == account.id && $0.hasSameIdentity(as: account) }) else { return nil }
        return accountAppearanceCache.appearance(for: account)
    }
    func fetchAccountAppearance(_ account: Account, using client: AccountAppearanceClient, forceRefresh: Bool = false) async throws -> AccountAppearance {
        try validateAppearanceAccount(account)
        if !forceRefresh, let cached = cachedAccountAppearance(account) { return cached }
        let appearance = try await client.load()
        try validateAppearanceAccount(account)
        accountAppearanceCache.save(appearance)
        return appearance
    }
    func fetchAccountTexture(_ texture: AccountTexture, kind: PlayerTextureKind, account: Account, using client: AccountAppearanceClient) async throws -> PlayerTextureImage {
        try validateAppearanceAccount(account)
        let cache = accountAppearanceCache
        if let image = try? cache.image(for: texture, kind: kind, account: account) { return image }
        let image = try await client.image(for: texture)
        try validateAppearanceAccount(account)
        try cache.save(image, for: texture, kind: kind, account: account)
        return image
    }
    func invalidateAccountAppearance(_ account: Account, uploaded texture: AccountTexture? = nil, kind: PlayerTextureKind = .skin) throws {
        let cache = accountAppearanceCache
        cache.invalidateAppearance(for: account)
        if let texture { try cache.invalidateImage(for: texture, kind: kind, account: account) }
    }
    private func validateAppearanceAccount(_ account: Account) throws {
        try Task.checkCancellation()
        guard !readOnly, state.accounts.contains(where: { $0.id == account.id && $0.hasSameIdentity(as: account) }) else {
            throw RuriError.message(Messages.AppAppModelAccounts.appearanceAccountChanged)
        }
    }
    func refreshAccountPreview(_ account: Account, forceRefresh: Bool = true) {
        // Keep startup and login prefetches independent of view lifetimes.
        Task {
            do {
                try await withAppearanceClient(for: account) { client in
                    let appearance = try await fetchAccountAppearance(account, using: client, forceRefresh: forceRefresh)
                    do { _ = try await fetchAccountSkin(appearance, using: client) }
                    catch {
                        try Task.checkCancellation()
                        report(Messages.AppAccountAppearanceView.appearanceError(error.localizedDescription), level: .warning)
                    }
                    // A failed skin download must not prevent the cape from loading.
                    let cape: PlayerTextureImage?
                    if let texture = appearance.activeCape {
                        cape = try await fetchAccountTexture(texture, kind: .cape, account: account, using: client)
                    } else { cape = nil }
                    try Task.checkCancellation()
                    try cacheAccountCape(cape, account: appearance.account)
                }
            } catch {
                if !Task.isCancelled {
                    report(Messages.AppAccountAppearanceView.appearanceError(error.localizedDescription), level: .warning)
                }
            }
        }
    }
    func fetchAccountSkin(_ appearance: AccountAppearance, using client: AccountAppearanceClient) async throws -> PlayerTextureImage? {
        let account = appearance.account
        if let texture = appearance.skin {
            let image = try await fetchAccountTexture(texture, kind: .skin, account: account, using: client)
            try Task.checkCancellation()
            try cacheAccountSkin(SavedPlayerSkin(name: String(appearance.playerName.prefix(80)), image: image, model: texture.model), account: account)
            return image
        }
        try Task.checkCancellation()
        try cacheAccountSkin(nil, account: account)
        return nil
    }
    func cacheAccountSkin(_ skin: SavedPlayerSkin?, account: Account) throws {
        guard !readOnly, state.accounts.contains(where: { $0.id == account.id && $0.uuid == account.uuid }) else {
            throw RuriError.message(Messages.AppAppModelAccounts.appearanceAccountChanged)
        }
        try SkinLibrary(paths: paths).setPreview(skin, for: account.id)
        accountSkins[account.id] = skin; loadedAccountPreviews.insert(account.id)
    }
    func cacheAccountCape(_ cape: PlayerTextureImage?, account: Account) throws {
        guard !readOnly, state.accounts.contains(where: { $0.id == account.id && $0.hasSameIdentity(as: account) }) else {
            throw RuriError.message(Messages.AppAppModelAccounts.appearanceAccountChanged)
        }
        try SkinLibrary(paths: paths).setCape(cape, for: account.id)
        accountCapes[account.id] = cape
    }
    func refreshAccount(_ account: Account) async throws {
        try await accountOperations.withLock(for: account.id) {
            try await refreshAccountSession(account)
            report(Messages.AppAppModelAccounts.credentialsRefreshed(state.accounts.first(where: { $0.id == account.id })?.username ?? account.username))
        }
    }
    private func refreshAccountSession(_ account: Account) async throws {
        guard !readOnly, state.accounts.contains(where: { $0.id == account.id && $0.hasSameIdentity(as: account) }) else {
            throw RuriError.message(Messages.AppAppModelAccounts.accountChanged)
        }
        switch account.kind {
        case .offline: return
        case .external: try await refreshExternal(account)
        case .microsoft:
            let credentials = try CredentialStore.load(for: account.id)
            let (updated, refreshed) = try await MicrosoftAuth(clientID: credentials.clientID).refresh(credentials, account: account)
            try addMicrosoft(updated, credentials: refreshed, activate: false, requireExisting: true)
            try Task.checkCancellation()
        }
    }
    func addOffline(_ username: String) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        let account = try Account(username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !state.accounts.contains(where: { $0.kind == .offline && $0.uuid == account.uuid }) else { throw RuriError.message(Messages.AppAppModelAccounts.offlineAccountExists) }
        var next = state; next.accounts.append(account); next.activeAccountID = account.id
        acceptState(try StateStore.save(next, to: paths, basedOn: persistedState))
    }
    @discardableResult func addMicrosoft(_ account: Account, credentials: AccountCredentials, activate: Bool = true, requireExisting: Bool = false) throws -> Account {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        guard !requireExisting || state.accounts.contains(where: { $0.id == account.id && $0.uuid == account.uuid }) else { throw RuriError.message(Messages.AppAppModelAccounts.accountChanged) }
        var account = account
        if let existing = state.accounts.first(where: { $0.kind == .microsoft && $0.uuid == account.uuid }) { account.id = existing.id }
        let existed = state.accounts.contains { $0.id == account.id }
        try CredentialStore.save(credentials, for: account.id)
        var next = state
        if let index = next.accounts.firstIndex(where: { $0.id == account.id }) { next.accounts[index] = account }
        else { next.accounts.append(account) }
        if activate { next.activeAccountID = account.id }
        do { acceptState(try StateStore.save(next, to: paths, basedOn: persistedState)) }
        catch { if !existed { try? CredentialStore.remove(for: account.id) }; throw error }
        return account
    }
    func removeAccount(_ account: Account) {
        do { try deleteAccount(account) } catch { self.error = error.localizedDescription }
    }
    private func deleteAccount(_ account: Account) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        var next = state
        next.accounts.removeAll { $0.id == account.id }
        if next.activeAccountID == account.id { next.activeAccountID = next.accounts.first?.id }
        acceptState(try StateStore.save(next, to: paths, basedOn: persistedState))
        accountSkins[account.id] = nil; accountCapes[account.id] = nil; loadedAccountPreviews.remove(account.id)
        // Credential cleanup must still happen if an appearance file is damaged.
        if account.kind == .microsoft { try CredentialStore.remove(for: account.id) }
        if account.kind == .external { try CredentialStore.removeExternal(for: account.id) }
        try accountAppearanceCache.remove(for: account)
        try SkinLibrary(paths: paths).setPreview(nil, for: account.id)
        try SkinLibrary(paths: paths).setCape(nil, for: account.id)
    }
    func addExternal(_ input: Account, credentials: ExternalAccountCredentials, requireExisting: Bool = false, activate: Bool = true) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        guard !requireExisting || state.accounts.contains(where: { $0.id == input.id && $0.hasSameIdentity(as: input) }) else { throw RuriError.message(Messages.AppAppModelAccounts.externalAccountRemoved) }
        var account = input
        let existing = state.accounts.first { $0.kind == .external && $0.uuid == input.uuid && $0.externalLogin?.server.url == input.externalLogin?.server.url && $0.externalLogin?.username == input.externalLogin?.username }
        if let existing { account.id = existing.id }
        try CredentialStore.saveExternal(credentials, for: account.id)
        var next = state
        if let index = next.accounts.firstIndex(where: { $0.id == account.id }) { next.accounts[index] = account }
        else { next.accounts.append(account) }
        if activate { next.activeAccountID = account.id }
        do { acceptState(try StateStore.save(next, to: paths, basedOn: persistedState)) }
        catch { if existing == nil { try? CredentialStore.removeExternal(for: account.id) }; throw error }
    }
    func refreshExternal(_ account: Account) async throws {
        let credentials = try CredentialStore.loadExternal(for: account.id)
        let (updated, refreshed) = try await ExternalAuthentication().refresh(account: account, credentials: credentials, force: true)
        try addExternal(updated, credentials: refreshed, requireExisting: true, activate: false)
        try Task.checkCancellation()
    }
    func logoutExternal(_ account: Account) async throws {
        try await accountOperations.withLock(for: account.id) {
            guard !readOnly, let server = account.externalLogin?.server,
                  state.accounts.contains(where: { $0.id == account.id && $0.hasSameIdentity(as: account) }) else {
                throw RuriError.message(Messages.AppAppModelAccounts.accountChanged)
            }
            try await ExternalAuthentication().invalidate(server: server, credentials: CredentialStore.loadExternal(for: account.id))
            try deleteAccount(account)
        }
    }
    func withAppearanceClient<T>(for requested: Account, operation: @MainActor (AccountAppearanceClient) async throws -> T) async throws -> T {
        try await accountOperations.withLock(for: requested.id) {
            do { return try await operation(appearanceClient(for: requested)) }
            catch AccountAppearanceError.loginExpired {
                try await refreshAccountSession(requested)
                return try await operation(appearanceClient(for: requested))
            }
        }
    }
    private func appearanceClient(for requested: Account) async throws -> AccountAppearanceClient {
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
