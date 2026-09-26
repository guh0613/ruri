import RuriLocalization
import Foundation

public protocol AccountCredentialVault: Sendable {
    func loadMicrosoft(_ id: UUID) throws -> AccountCredentials
    func saveMicrosoft(_ credentials: AccountCredentials, _ id: UUID) throws
    func loadExternal(_ id: UUID) throws -> ExternalAccountCredentials
    func saveExternal(_ credentials: ExternalAccountCredentials, _ id: UUID) throws
    func remove(_ id: UUID, kind: Account.Kind) throws
    func loadFlow(_ id: UUID) throws -> Data
    func saveFlow(_ data: Data, _ id: UUID) throws
    func removeFlow(_ id: UUID) throws
    func flowIDs() throws -> [UUID]
}

public struct SystemAccountCredentialVault: AccountCredentialVault {
    public init() {}
    public func loadMicrosoft(_ id: UUID) throws -> AccountCredentials { try CredentialStore.load(for: id) }
    public func saveMicrosoft(_ credentials: AccountCredentials, _ id: UUID) throws { try CredentialStore.save(credentials, for: id) }
    public func loadExternal(_ id: UUID) throws -> ExternalAccountCredentials { try CredentialStore.loadExternal(for: id) }
    public func saveExternal(_ credentials: ExternalAccountCredentials, _ id: UUID) throws { try CredentialStore.saveExternal(credentials, for: id) }
    public func remove(_ id: UUID, kind: Account.Kind) throws {
        if kind == .microsoft { try CredentialStore.remove(for: id) }
        if kind == .external { try CredentialStore.removeExternal(for: id) }
    }
    public func loadFlow(_ id: UUID) throws -> Data { try CredentialStore.loadFlow(for: id) }
    public func saveFlow(_ data: Data, _ id: UUID) throws { try CredentialStore.saveFlow(data, for: id) }
    public func removeFlow(_ id: UUID) throws { try CredentialStore.removeFlow(for: id) }
    public func flowIDs() throws -> [UUID] { try CredentialStore.flowIDs() }
}

/// The lease lasts for the authenticated operation, not just the Keychain read.
/// This type contains secrets and is intentionally not Codable.
public final class AuthenticatedAccount: Sendable {
    public let account: Account
    public let accessToken: String
    public let externalCredentials: ExternalAccountCredentials?
    public let secrets: [String]
    private let lease: OperationLease
    init(account: Account, accessToken: String, external: ExternalAccountCredentials? = nil, secrets: [String], lease: OperationLease) {
        self.account = account; self.accessToken = accessToken; externalCredentials = external; self.secrets = secrets; self.lease = lease
    }
}

@MainActor public struct AccountService: Sendable {
    public let paths: LauncherPaths
    let vault: any AccountCredentialVault
    let lockDirectory: URL
    let session: URLSession
    // Keychain items are user-wide, including when --data-dir differs.
    public init(paths: LauncherPaths, vault: any AccountCredentialVault = SystemAccountCredentialVault(), lockDirectory: URL? = nil, session: URLSession = .shared) {
        self.paths = paths; self.vault = vault; self.session = session
        self.lockDirectory = lockDirectory ?? LauncherPaths().root.appendingPathComponent(".account-locks")
    }
    func lock(_ id: UUID) throws -> OperationLease { try OperationLease.acquire(directory: lockDirectory, name: id.uuidString + ".lock") }
    public func account(_ id: UUID) throws -> Account {
        guard let account = try StateStore.load(paths).accounts.first(where: { $0.id == id }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.te9b1e0403a1e.localized) }; return account
    }
    @discardableResult public func addOffline(_ username: String, activate: Bool = true) throws -> Account {
        let created = try Account(username: username.trimmingCharacters(in: .whitespacesAndNewlines))
        var result = created
        try StateStore.updateIfChanged(paths) { state in
            if let existing = state.accounts.first(where: { $0.hasSameIdentity(as: created) }) { result = existing }
            else { state.accounts.append(created) }
            if activate { state.activeAccountID = result.id }
        }
        return result
    }
    @discardableResult public func select(_ id: UUID) throws -> PersistentState {
        try StateStore.updateIfChanged(paths) { state in
            guard state.accounts.contains(where: { $0.id == id }) else { throw OperationFailure("NOT_FOUND", Messages.CLIInterface.te9b1e0403a1e.localized) }
            state.activeAccountID = id
        }
    }
    @discardableResult public func store(_ input: Account, microsoft: AccountCredentials? = nil, external: ExternalAccountCredentials? = nil, activate: Bool = true, requireExisting: Bool = false) throws -> Account {
        let registration = try OperationLease.acquire(directory: lockDirectory, name: "registration.lock")
        defer { withExtendedLifetime(registration) {} }
        var account = input
        if let existing = try StateStore.load(paths).accounts.first(where: { $0.hasSameIdentity(as: input) }) { account.id = existing.id }
        let lease = try lock(account.id); defer { withExtendedLifetime(lease) {} }
        try commit(account, microsoft: microsoft, external: external, activate: activate, requireExisting: requireExisting)
        return account
    }
    private func commit(_ account: Account, microsoft: AccountCredentials?, external: ExternalAccountCredentials?, activate: Bool, requireExisting: Bool) throws {
        let existing = try StateStore.load(paths).accounts.first { $0.id == account.id }
        guard !requireExisting || existing?.hasSameIdentity(as: account) == true else { throw OperationFailure("ACCOUNT_CHANGED", Messages.CLIInterface.tb0b930baf0cc.localized) }
        guard existing == nil || existing!.hasSameIdentity(as: account) else { throw OperationFailure("ACCOUNT_CHANGED", Messages.CLIInterface.t9b5e04245098.localized) }
        if let microsoft { try vault.saveMicrosoft(microsoft, account.id) }
        if let external { try vault.saveExternal(external, account.id) }
        do {
            try StateStore.updateIfChanged(paths) { state in
                if let index = state.accounts.firstIndex(where: { $0.id == account.id }) {
                    guard state.accounts[index].hasSameIdentity(as: account) else { throw OperationFailure("ACCOUNT_CHANGED", Messages.CLIInterface.t9b5e04245098.localized) }
                    state.accounts[index] = account
                } else {
                    guard !requireExisting else { throw OperationFailure("ACCOUNT_CHANGED", Messages.CLIInterface.td9ca8e4b44c6.localized) }
                    state.accounts.append(account)
                }
                if activate { state.activeAccountID = account.id }
            }
        } catch {
            // Refresh can invalidate old tokens: retain new tokens for an
            // existing identity; only remove newly created orphan credentials.
            if existing == nil { try? vault.remove(account.id, kind: account.kind) }
            throw error
        }
    }
    public func authenticate(_ id: UUID, forceRefresh: Bool = false) async throws -> AuthenticatedAccount {
        let lease = try lock(id), account = try account(id)
        var redactor = GameLogRedactor()
        do {
            switch account.kind {
            case .offline: return .init(account: account, accessToken: "0", secrets: [], lease: lease)
            case .microsoft:
                var credentials = try vault.loadMicrosoft(id), updated = account
                let prior = [credentials.accessToken, credentials.refreshToken]; redactor.addSecrets(prior)
                if forceRefresh || credentials.expiresAt < Date().addingTimeInterval(120) {
                    (updated, credentials) = try await MicrosoftAuth(clientID: credentials.clientID, session: session).refresh(credentials, account: account)
                    redactor.addSecrets([credentials.accessToken, credentials.refreshToken])
                    try commit(updated, microsoft: credentials, external: nil, activate: false, requireExisting: true)
                }
                return .init(account: updated, accessToken: credentials.accessToken, secrets: prior + [credentials.accessToken, credentials.refreshToken], lease: lease)
            case .external:
                let original = try vault.loadExternal(id); redactor.addSecrets([original.accessToken, original.clientToken])
                let (updated, credentials) = try await ExternalAuthentication(session: session).refresh(account: account, credentials: original, force: forceRefresh)
                redactor.addSecrets([credentials.accessToken, credentials.clientToken])
                try commit(updated, microsoft: nil, external: credentials, activate: false, requireExisting: true)
                return .init(account: updated, accessToken: credentials.accessToken, external: credentials,
                             secrets: [original.accessToken, original.clientToken, credentials.accessToken, credentials.clientToken], lease: lease)
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as OperationFailure { throw error }
        catch { throw OperationFailure("AUTHENTICATION_REQUIRED", redactor.redact(error.localizedDescription), nextActions: [.init(["account", "login", "start", "--provider", account.kind.rawValue, "--account", id.uuidString])]) }
    }
    @discardableResult public func remove(_ id: UUID) throws -> PersistentState {
        let lease = try lock(id); defer { withExtendedLifetime(lease) {} }
        return try removeLocked(id)
    }
    private func removeLocked(_ id: UUID) throws -> PersistentState {
        let removed = try StateStore.load(paths).accounts.first { $0.id == id }
        let saved = try StateStore.updateIfChanged(paths) { state in
            state.accounts.removeAll { $0.id == id }
            if state.activeAccountID == id { state.activeAccountID = state.accounts.first?.id }
        }
        do {
            if removed?.kind != .offline { try vault.remove(id, kind: .microsoft); try vault.remove(id, kind: .external) }
            if let removed { try AccountAppearanceCache(paths: paths).remove(for: removed) }
            try SkinLibrary(paths: paths).setPreview(nil, for: id); try SkinLibrary(paths: paths).setCape(nil, for: id)
        } catch { throw OperationFailure("CREDENTIAL_CLEANUP_REQUIRED", Messages.CLIInterface.tf4c5f25a3baf.localized, retryable: true, nextActions: [.init(["account", "remove", id.uuidString, "--yes"])]) }
        return saved
    }
    @discardableResult public func logout(_ id: UUID) async throws -> PersistentState {
        let lease = try lock(id); defer { withExtendedLifetime(lease) {} }
        let account = try account(id)
        if account.kind == .external, let server = account.externalLogin?.server { try await ExternalAuthentication(session: session).invalidate(server: server, credentials: vault.loadExternal(id)) }
        return try removeLocked(id)
    }
}
