import Foundation
import Testing
@testable import RuriCore

final class TestCredentialVault: AccountCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private var microsoft: [UUID: AccountCredentials] = [:]
    private var external: [UUID: ExternalAccountCredentials] = [:]
    private var flows: [UUID: Data] = [:]
    func loadMicrosoft(_ id: UUID) throws -> AccountCredentials { try lock.withLock { guard let v = microsoft[id] else { throw OperationFailure("MISSING", "missing") }; return v } }
    func saveMicrosoft(_ credentials: AccountCredentials, _ id: UUID) throws { lock.withLock { microsoft[id] = credentials } }
    func loadExternal(_ id: UUID) throws -> ExternalAccountCredentials { try lock.withLock { guard let v = external[id] else { throw OperationFailure("MISSING", "missing") }; return v } }
    func saveExternal(_ credentials: ExternalAccountCredentials, _ id: UUID) throws { lock.withLock { external[id] = credentials } }
    func remove(_ id: UUID, kind: Account.Kind) throws { lock.withLock { if kind == .microsoft { microsoft[id] = nil }; if kind == .external { external[id] = nil } } }
    func loadFlow(_ id: UUID) throws -> Data { try lock.withLock { guard let v = flows[id] else { throw OperationFailure("MISSING", "missing") }; return v } }
    func saveFlow(_ data: Data, _ id: UUID) throws { lock.withLock { flows[id] = data } }
    func removeFlow(_ id: UUID) throws { lock.withLock { flows[id] = nil } }
    func flowIDs() throws -> [UUID] { lock.withLock { Array(flows.keys) } }
}

@MainActor struct AccountServiceTests {
    @Test func offlineCreationIsIdempotent() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = AccountService(paths: paths, vault: TestCredentialVault(), lockDirectory: paths.root.appendingPathComponent("locks"))
        let first = try service.addOffline("Player")
        let bytes = try Data(contentsOf: paths.state)
        #expect(try service.addOffline("Player").id == first.id)
        #expect(try Data(contentsOf: paths.state) == bytes)
    }
    @Test func credentialsStayLeasedUntilTheOperationEnds() async throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let vault = TestCredentialVault(), locks = paths.root.appendingPathComponent("locks")
        let service = AccountService(paths: paths, vault: vault, lockDirectory: locks)
        let account = Account(username: "Player", uuid: AccountTestFixtures.uuid, kind: .microsoft)
        let credentials = AccountCredentials(accessToken: "private-access", refreshToken: "private-refresh", expiresAt: Date().addingTimeInterval(3600), clientID: UUID().uuidString)
        try service.store(account, microsoft: credentials)
        do {
            let authenticated = try await service.authenticate(account.id)
            defer { withExtendedLifetime(authenticated) {} }
            #expect(authenticated.accessToken == credentials.accessToken)
            #expect(throws: OperationFailure.self) { try service.remove(account.id) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = ["-c", "import fcntl,sys\nf=open(sys.argv[1], 'r+')\ntry: fcntl.lockf(f, fcntl.LOCK_EX|fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(23)\nsys.exit(0)", locks.appendingPathComponent(account.id.uuidString + ".lock").path]
            try process.run(); process.waitUntilExit()
            #expect(process.terminationStatus == 23)
        }
        try service.remove(account.id)
        #expect(try StateStore.load(paths).accounts.isEmpty)
        #expect(throws: OperationFailure.self) { try vault.loadMicrosoft(account.id) }
        #expect(throws: OperationFailure.self) { try service.store(account, microsoft: credentials, requireExisting: true) }
        #expect(try StateStore.load(paths).accounts.isEmpty)
    }
    @Test func pendingLoginDoesNotExposeDeviceSecretAndExpires() async throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let vault = TestCredentialVault()
        try StateStore.update(paths) { $0.settings.microsoftClientID = UUID().uuidString }
        let stub = EndpointHTTPFixture(["login.microsoftonline.com/consumers/oauth2/v2.0/devicecode": Data(#"{"device_code":"PRIVATE_DEVICE_SECRET","user_code":"USER-CODE","verification_uri":"https://www.microsoft.com/link","expires_in":0,"interval":1}"#.utf8)])
        defer { stub.close() }
        let service = AccountService(paths: paths, vault: vault, lockDirectory: paths.root.appendingPathComponent("locks"), session: stub.session)
        let response = try await service.startMicrosoft(), id = try #require(response["flowID"].string.flatMap(UUID.init(uuidString:)))
        #expect(!String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains("PRIVATE_DEVICE_SECRET"))
        #expect(response["userCode"] == .string("USER-CODE"))
        do { _ = try await service.completeLogin(id); Issue.record("Expected expiry") }
        catch let error as OperationFailure { #expect(error.code == "LOGIN_EXPIRED") }
        #expect(try vault.flowIDs().isEmpty)
        #expect(try StateStore.load(paths).accounts.isEmpty)
    }
    @Test func microsoftFlowCompletesAndStoresOnlyProfileMetadata() async throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let vault = TestCredentialVault()
        try StateStore.update(paths) { $0.settings.microsoftClientID = UUID().uuidString }
        let stub = EndpointHTTPFixture([
            "login.microsoftonline.com/consumers/oauth2/v2.0/devicecode": Data(#"{"device_code":"device-secret","user_code":"USER","verification_uri":"https://www.microsoft.com/link","expires_in":300,"interval":1}"#.utf8),
            "login.microsoftonline.com/consumers/oauth2/v2.0/token": Data(#"{"access_token":"oauth-secret","refresh_token":"refresh-secret"}"#.utf8),
            "user.auth.xboxlive.com/user/authenticate": Data(#"{"Token":"xbox-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "xsts.auth.xboxlive.com/xsts/authorize": Data(#"{"Token":"xsts-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "api.minecraftservices.com/authentication/login_with_xbox": Data(#"{"access_token":"minecraft-secret","expires_in":3600}"#.utf8),
            "api.minecraftservices.com/entitlements/mcstore": Data(#"{"items":[]}"#.utf8),
            "api.minecraftservices.com/minecraft/profile": Data(#"{"id":"0123456789abcdef0123456789abcdef","name":"Player"}"#.utf8)
        ])
        defer { stub.close() }
        let service = AccountService(paths: paths, vault: vault, lockDirectory: paths.root.appendingPathComponent("locks"), session: stub.session)
        let response = try await service.startMicrosoft(), id = try #require(response["flowID"].string.flatMap(UUID.init(uuidString:)))
        let account = try await service.completeLogin(id)
        #expect(account.kind == .microsoft)
        #expect(try vault.loadMicrosoft(account.id).accessToken == "minecraft-secret")
        #expect(try vault.flowIDs().isEmpty)
        #expect(try !String(contentsOf: paths.state, encoding: .utf8).contains("secret"))
    }
}
