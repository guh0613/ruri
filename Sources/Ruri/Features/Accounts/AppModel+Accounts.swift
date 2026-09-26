import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func activateAccount(_ account: Account) {
        guard !readOnly, state.accounts.contains(where: { $0.id == account.id }) else { return }
        do { acceptState(try AccountService(paths: basePaths).select(account.id)) }
        catch { self.error = error.localizedDescription }
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
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        let authenticated = try await AccountService(paths: basePaths).authenticate(account.id, forceRefresh: true)
        defer { withExtendedLifetime(authenticated) {} }
        acceptState(try StateStore.load(basePaths))
        report(Messages.AppAppModelAccounts.credentialsRefreshed(authenticated.account.username))
    }
    func addOffline(_ username: String) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        _ = try AccountService(paths: basePaths).addOffline(username)
        acceptState(try StateStore.load(basePaths))
    }
    @discardableResult func addMicrosoft(_ account: Account, credentials: AccountCredentials, activate: Bool = true, requireExisting: Bool = false) throws -> Account {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        let saved = try AccountService(paths: basePaths).store(account, microsoft: credentials, activate: activate, requireExisting: requireExisting)
        acceptState(try StateStore.load(basePaths)); return saved
    }
    func removeAccount(_ account: Account) {
        do {
            guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
            acceptState(try AccountService(paths: basePaths).remove(account.id))
            accountSkins[account.id] = nil; accountCapes[account.id] = nil; loadedAccountPreviews.remove(account.id)
            try accountAppearanceCache.remove(for: account)
        } catch { self.error = error.localizedDescription }
    }
    func addExternal(_ account: Account, credentials: ExternalAccountCredentials, requireExisting: Bool = false, activate: Bool = true) throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        _ = try AccountService(paths: basePaths).store(account, external: credentials, activate: activate, requireExisting: requireExisting)
        acceptState(try StateStore.load(basePaths))
    }
    func refreshExternal(_ account: Account) async throws { try await refreshAccount(account) }
    func logoutExternal(_ account: Account) async throws {
        guard !readOnly else { throw RuriError.message(Messages.AppAppModelAccounts.accountWritePaused) }
        acceptState(try await AccountService(paths: basePaths).logout(account.id))
        accountSkins[account.id] = nil; accountCapes[account.id] = nil; loadedAccountPreviews.remove(account.id)
        try accountAppearanceCache.remove(for: account)
    }
    func withAppearanceClient<T>(for requested: Account, operation: @MainActor (AccountAppearanceClient) async throws -> T) async throws -> T {
        try await accountOperations.withLock(for: requested.id) {
            @MainActor func attempt(force: Bool) async throws -> T {
                try validateAppearanceAccount(requested)
                let authenticated = try await AccountService(paths: basePaths).authenticate(requested.id, forceRefresh: force)
                defer { withExtendedLifetime(authenticated) {} }
                guard authenticated.account.hasSameIdentity(as: requested), authenticated.account.kind != .offline else {
                    throw RuriError.message(Messages.AppAppModelAccounts.appearanceAccountChanged)
                }
                acceptState(try StateStore.load(basePaths))
                return try await operation(AccountAppearanceClient(account: authenticated.account, accessToken: authenticated.accessToken))
            }
            do { return try await attempt(force: false) }
            catch AccountAppearanceError.loginExpired { return try await attempt(force: true) }
        }
    }
}
