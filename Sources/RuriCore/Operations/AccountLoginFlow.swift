import RuriLocalization
import Foundation

extension AccountService {
    private struct LoginFlow: Codable {
        let id: UUID
        let expiresAt: Date
        let dataDirectory: String
        var accountID: UUID?
        var deviceCode: DeviceCode?
        var clientID: String?
        var externalSession: ExternalAuthSession?
        var server: ExternalAuthServer?
        var username: String?
    }
    public func startMicrosoft(accountID: UUID? = nil) async throws -> OperationValue {
        try pruneFlows()
        if let accountID { guard try account(accountID).kind == .microsoft else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t646f7af4624c.localized) } }
        let client = try StateStore.load(paths).settings.effectiveMicrosoftClientID
        let code = try await MicrosoftAuth(clientID: client, session: session).begin()
        let flow = LoginFlow(id: UUID(), expiresAt: Date().addingTimeInterval(TimeInterval(code.expires_in)), dataDirectory: paths.root.standardizedFileURL.path,
                             accountID: accountID, deviceCode: code, clientID: client)
        try vault.saveFlow(JSONEncoder().encode(flow), flow.id)
        return .object(["flowID": .string(flow.id.uuidString), "verificationURL": .string(code.verification_uri.absoluteString), "userCode": .string(code.user_code), "expiresAt": .string(flow.expiresAt.ISO8601Format())])
    }
    public func startExternal(server address: String, username: String, password: String, accountID: UUID? = nil) async throws -> OperationValue {
        try pruneFlows()
        let service = ExternalAuthentication(session: session), metadata = try await service.discover(address)
        if let accountID {
            let existing = try account(accountID)
            guard existing.kind == .external, existing.externalLogin?.server.url == metadata.server.url, existing.externalLogin?.username == username else { throw OperationFailure("ACCOUNT_CHANGED", Messages.CLIInterface.t3a1a6178fec9.localized) }
        }
        let result = try await service.login(server: metadata.server, username: username, password: password)
        let flow = LoginFlow(id: UUID(), expiresAt: Date().addingTimeInterval(600), dataDirectory: paths.root.standardizedFileURL.path,
                             accountID: accountID, externalSession: result, server: metadata.server, username: username)
        try vault.saveFlow(JSONEncoder().encode(flow), flow.id)
        return .object(["flowID": .string(flow.id.uuidString), "expiresAt": .string(flow.expiresAt.ISO8601Format()), "server": .string(metadata.server.url.absoluteString),
            "selectedProfile": .text(result.selectedProfile?.id), "profiles": .array((result.availableProfiles ?? []).map { .object(["id": .string($0.id), "name": .string($0.name)]) })])
    }
    public func completeLogin(_ id: UUID, profile: String? = nil) async throws -> Account {
        let flowLease = try OperationLease.acquire(directory: lockDirectory, name: "flow-\(id).lock")
        defer { withExtendedLifetime(flowLease) {} }
        let flow = try JSONDecoder().decode(LoginFlow.self, from: vault.loadFlow(id))
        guard flow.dataDirectory == paths.root.standardizedFileURL.path else { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t000e28c5735c.localized) }
        guard flow.expiresAt > Date() else { try vault.removeFlow(id); throw OperationFailure("LOGIN_EXPIRED", Messages.CLIInterface.tf873deb7e49d.localized) }
        let account: Account
        if let code = flow.deviceCode, let client = flow.clientID {
            var (result, credentials) = try await MicrosoftAuth(clientID: client, session: session).finish(code, expiresAt: flow.expiresAt)
            if let id = flow.accountID { result = try self.account(id).reauthenticated(with: result) }
            account = try store(result, microsoft: credentials, activate: flow.accountID == nil, requireExisting: flow.accountID != nil)
        } else if var result = flow.externalSession, let server = flow.server, let username = flow.username {
            if result.selectedProfile == nil {
                guard let profile, let selected = result.availableProfiles?.first(where: { $0.id == profile }) else { throw OperationFailure("PROFILE_REQUIRED", Messages.CLIInterface.ta4020b2f41c3.localized) }
                result = try await ExternalAuthentication(session: session).select(selected, from: result, server: server)
            } else if let profile, result.selectedProfile?.id != profile { throw OperationFailure("INVALID_ARGUMENT", Messages.CLIInterface.t0ce4aa2e33ec.localized) }
            let existing = try flow.accountID.map(self.account)
            account = try store(result.account(server: server, username: username, replacing: existing), external: result.credentials, activate: existing == nil, requireExisting: existing != nil)
        } else { throw OperationFailure("LOGIN_EXPIRED", Messages.CLIInterface.t6176d717fcb9.localized) }
        try vault.removeFlow(id); return account
    }
    public func cancelLogin(_ id: UUID) throws {
        let lease = try OperationLease.acquire(directory: lockDirectory, name: "flow-\(id).lock"); defer { withExtendedLifetime(lease) {} }
        try vault.removeFlow(id)
    }
    private func pruneFlows() throws {
        for id in try vault.flowIDs() {
            guard let lease = try? OperationLease.acquire(directory: lockDirectory, name: "flow-\(id).lock") else { continue }
            defer { withExtendedLifetime(lease) {} }
            let flow = try? JSONDecoder().decode(LoginFlow.self, from: vault.loadFlow(id))
            if flow == nil || flow!.expiresAt <= Date() { try vault.removeFlow(id) }
        }
    }
}
