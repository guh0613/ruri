import Foundation
import RuriLocalization
import Testing
@testable import RuriCore

struct AuthenticationTests {
    private static let responses: [String: Data] = [
            "login.microsoftonline.com/consumers/oauth2/v2.0/devicecode": Data(#"{"device_code":"device+&=","user_code":"USER","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":1}"#.utf8),
            "login.microsoftonline.com/consumers/oauth2/v2.0/token": Data(#"{"access_token":"oauth-access","refresh_token":"oauth-refresh"}"#.utf8),
            "user.auth.xboxlive.com/user/authenticate": Data(#"{"Token":"xbox-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "xsts.auth.xboxlive.com/xsts/authorize": Data(#"{"Token":"xsts-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "api.minecraftservices.com/authentication/login_with_xbox": Data(#"{"access_token":"minecraft-token","expires_in":3600}"#.utf8),
            "api.minecraftservices.com/entitlements/mcstore": Data(#"{"items":[{"name":"game_minecraft"}]}"#.utf8),
            "api.minecraftservices.com/minecraft/profile": Data(#"{"id":"profile-id","name":"Player"}"#.utf8)
        ]

    @Test(arguments: [false, true])
    func refreshPreservesIdentityAndRotatesTokensWhenAvailable(rotatesToken: Bool) async throws {
        var responses = Self.responses
        if !rotatesToken {
            responses["login.microsoftonline.com/consumers/oauth2/v2.0/token"] = Data(#"{"access_token":"oauth-access"}"#.utf8)
        }
        let stub = EndpointHTTPFixture(responses)
        defer { stub.close() }
        let (account, credentials) = try await MicrosoftAuth(clientID: Self.oldCredentials.clientID, session: stub.session)
            .refresh(Self.oldCredentials, account: Self.account)
        #expect(account.id == Self.account.id && account.username == "Player")
        #expect(credentials.accessToken == "minecraft-token")
        #expect(credentials.refreshToken == (rotatesToken ? "oauth-refresh" : Self.oldCredentials.refreshToken))
        #expect(credentials.clientID == Self.oldCredentials.clientID && credentials.expiresAt > Date())
        let token = try #require(stub.requests.first { $0.url == AuthenticationEndpoints.token })
        #expect(String(decoding: token.body, as: UTF8.self).contains("refresh_token=refresh%2B%26%3D"))
        for (endpoint, relyingParty) in [(AuthenticationEndpoints.xboxAuthenticate, "http://auth.xboxlive.com"),
                                         (AuthenticationEndpoints.xstsAuthorize, "rp://api.minecraftservices.com/")] {
            let request = try #require(stub.requests.first { $0.url == endpoint })
            let payload = try #require(try JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            #expect(payload["RelyingParty"] as? String == relyingParty)
        }
        let login = try #require(stub.requests.first { $0.url == AuthenticationEndpoints.minecraftLogin })
        let body = try JSONDecoder().decode([String: String].self, from: login.body)
        #expect(body["identityToken"] == "XBL3.0 x=user-hash;xsts-token")
        for endpoint in [AuthenticationEndpoints.entitlements, AuthenticationEndpoints.profile] {
            #expect(stub.requests.first { $0.url == endpoint }?.header("Authorization") == "Bearer minecraft-token")
        }
        #expect(stub.requests.filter { $0.url.host != "api.minecraftservices.com" }.allSatisfy { $0.header("Authorization") == nil })
    }

    @Test func deviceLoginAcceptsAJavaProfileEvenWhenStoreItemsAreEmpty() async throws {
        var responses = Self.responses
        responses["api.minecraftservices.com/entitlements/mcstore"] = Data(#"{"items":[]}"#.utf8)
        let stub = EndpointHTTPFixture(responses)
        defer { stub.close() }
        let clientID = UUID().uuidString, service = MicrosoftAuth(clientID: clientID, session: stub.session)
        let code = try await service.begin()
        let (account, credentials) = try await service.finish(code)
        #expect(account.kind == .microsoft && account.username == "Player")
        #expect(credentials.clientID == clientID && credentials.refreshToken == "oauth-refresh")
        let request = try #require(stub.requests.first { $0.url == AuthenticationEndpoints.token })
        let form = String(decoding: request.body, as: UTF8.self)
        #expect(form.contains("device_code=device%2B%26%3D") && form.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
    }

    @Test(arguments: [false, true])
    func missingJavaProfileDistinguishesLicenseFromProfileSetup(ownsJava: Bool) async throws {
        let stub = EndpointHTTPFixture { request in
            if request.url == AuthenticationEndpoints.profile { return .init(status: 404) }
            if request.url == AuthenticationEndpoints.license {
                return .init(data: Data((ownsJava ? #"{"items":[{"name":"game_minecraft"}]}"# : #"{"items":[{"name":"unrelated_product"}]}"#).utf8))
            }
            return Self.responses[(request.url.host ?? "") + request.url.path].map { .init(data: $0) }
        }
        defer { stub.close() }
        do {
            _ = try await MicrosoftAuth(clientID: UUID().uuidString, session: stub.session).refresh(Self.oldCredentials, account: Self.account)
            Issue.record("An account without a Java profile was accepted")
        } catch let error as RuriError {
            #expect(error.messageID == (ownsJava ? Messages.CoreAuthentication.minecraftJavaProfileMissing.key : Messages.CoreAuthentication.minecraftJavaEntitlementMissing.key))
        }
    }

    @Test func profileServiceFailureDoesNotBecomeAnOwnershipError() async throws {
        let stub = EndpointHTTPFixture { request in
            if request.url == AuthenticationEndpoints.profile { return .init(status: 503) }
            return Self.responses[(request.url.host ?? "") + request.url.path].map { .init(data: $0) }
        }
        defer { stub.close() }
        do {
            _ = try await MicrosoftAuth(clientID: UUID().uuidString, session: stub.session).refresh(Self.oldCredentials, account: Self.account)
            Issue.record("An unavailable profile service was accepted")
        } catch let error as RuriError { #expect(error.httpStatusCode == 503) }
        #expect(!stub.requests.contains { $0.url == AuthenticationEndpoints.license })
    }

    @Test(arguments: ["authorization_declined", "expired_token"])
    func deviceLoginReportsCancellationAndExpiry(errorCode: String) async throws {
        let stub = EndpointHTTPFixture { request in
            guard request.url == AuthenticationEndpoints.token else { return nil }
            return .init(data: Data("{\"error\":\"\(errorCode)\"}".utf8), status: 400)
        }
        defer { stub.close() }
        let code = try JSONDecoder().decode(DeviceCode.self, from: Data(#"{"device_code":"device","user_code":"USER","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":1}"#.utf8))
        do {
            _ = try await MicrosoftAuth(clientID: UUID().uuidString, session: stub.session).finish(code)
            Issue.record("A declined or expired login was accepted")
        } catch let error as RuriError {
            #expect(error.messageID == (errorCode == "authorization_declined" ? Messages.CoreAuthentication.loginCancelled.key : Messages.CoreAuthentication.deviceLoginCodeExpired.key))
        }
        #expect(stub.requests.count == 1)
    }

    @Test func reauthenticationPreservesAccountIdentityAndRejectsAnotherPlayer() throws {
        let original = Account(username: "OldName", uuid: "0123456789abcdef0123456789abcdef", kind: .microsoft)
        let renamed = Account(username: "NewName", uuid: "01234567-89AB-CDEF-0123-456789ABCDEF", kind: .microsoft)
        let updated = try original.reauthenticated(with: renamed)
        #expect(updated.id == original.id && updated.username == "NewName")
        #expect(throws: (any Error).self) { try original.reauthenticated(with: Account(username: "Other", uuid: String(repeating: "f", count: 32), kind: .microsoft)) }
        #expect(throws: (any Error).self) { try original.reauthenticated(with: Account(username: "Offline")) }
    }

    private static let account = Account(username: "OldName", uuid: "profile-id", kind: .microsoft)
    private static let oldCredentials = AccountCredentials(accessToken: "old", refreshToken: "refresh+&=", expiresAt: .distantPast, clientID: "df01d133-3715-49b0-a48f-31e486c76402")
}
