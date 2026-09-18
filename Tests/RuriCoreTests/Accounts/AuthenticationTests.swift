import Foundation
import RuriLocalization
import Testing
@testable import RuriCore

struct AuthenticationTests {
    @Test func distributionDefaultsPreserveAccountConfigurationOverrides() throws {
        let bundledID = UUID().uuidString, customID = UUID().uuidString
        let configuration = BuildConfiguration(info: ["RuriMicrosoftClientID": bundledID, "RuriVersion": "0.2.0-beta.1", "CFBundleShortVersionString": "0.2.0"])
        let oldSettings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"concurrentDownloads":8,"microsoftClientID":"","showSnapshots":false,"defaultMemoryMB":4096,"appearance":"system"}"#.utf8))
        #expect(configuration.microsoftClientID(override: oldSettings.microsoftClientID) == bundledID)
        #expect(configuration.microsoftClientID(override: " \n") == bundledID)
        #expect(configuration.microsoftClientID(override: " \(customID)\n") == customID)
        #expect(configuration.version == "0.2.0-beta.1")
        #expect(BuildConfiguration(info: [:]).microsoftClientID(override: "") == "")
        #expect(BuildConfiguration(info: [:]).microsoftClientID(override: customID) == customID)
    }

    private static let responses: [String: Data] = [
            "login.microsoftonline.com/consumers/oauth2/v2.0/devicecode": Data(#"{"device_code":"device","user_code":"USER","verification_uri":"https://www.microsoft.com/link","expires_in":900}"#.utf8),
            "login.microsoftonline.com/consumers/oauth2/v2.0/token": Data(#"{"access_token":"oauth-access","refresh_token":"oauth-refresh"}"#.utf8),
            "user.auth.xboxlive.com/user/authenticate": Data(#"{"Token":"xbox-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "xsts.auth.xboxlive.com/xsts/authorize": Data(#"{"Token":"xsts-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "api.minecraftservices.com/authentication/login_with_xbox": Data(#"{"access_token":"minecraft-token","expires_in":3600}"#.utf8),
            "api.minecraftservices.com/entitlements/mcstore": Data(#"{"items":[{"name":"game_minecraft"}]}"#.utf8),
            "api.minecraftservices.com/minecraft/profile": Data(#"{"id":"profile-id","name":"Player"}"#.utf8)
        ]

    @Test func configuredSessionExercisesOfficialAuthenticationExchange() async throws {
        let stub = EndpointHTTPFixture(Self.responses)
        defer { stub.close() }
        let clientID = UUID().uuidString, service = MicrosoftAuth(clientID: clientID, session: stub.session)
        #expect(try await service.begin().user_code == "USER")
        let original = Account(username: "OldName", uuid: "profile-id", kind: .microsoft)
        let (account, credentials) = try await service.refresh(.init(accessToken: "old", refreshToken: "refresh+&=", expiresAt: .distantPast, clientID: clientID), account: original)
        #expect(account.id == original.id && account.username == "Player")
        #expect(credentials.accessToken == "minecraft-token" && credentials.refreshToken == "oauth-refresh" && credentials.clientID == clientID)
        let requests = stub.requests
        #expect(requests.map(\.url) == [AuthenticationEndpoints.deviceCode, AuthenticationEndpoints.token, AuthenticationEndpoints.xboxAuthenticate, AuthenticationEndpoints.xstsAuthorize, AuthenticationEndpoints.minecraftLogin, AuthenticationEndpoints.entitlements, AuthenticationEndpoints.profile])
        #expect(requests.map(\.method) == ["POST", "POST", "POST", "POST", "POST", "GET", "GET"])
        #expect(String(decoding: requests[1].body, as: UTF8.self).contains("refresh_token=refresh%2B%26%3D"))
        let xbox = try #require(try JSONSerialization.jsonObject(with: requests[2].body) as? [String: Any])
        let xsts = try #require(try JSONSerialization.jsonObject(with: requests[3].body) as? [String: Any])
        #expect(xbox["RelyingParty"] as? String == "http://auth.xboxlive.com")
        #expect(xsts["RelyingParty"] as? String == "rp://api.minecraftservices.com/")
        #expect(requests.prefix(5).allSatisfy { $0.header("Authorization") == nil })
        #expect(requests.suffix(2).allSatisfy { $0.header("Authorization") == "Bearer minecraft-token" })
        #expect(requests.allSatisfy { $0.url.scheme == "https" && $0.url.query == nil && $0.url.fragment == nil })
    }

    @Test func deviceLoginAcceptsAJavaProfileEvenWhenStoreItemsAreEmpty() async throws {
        var responses = Self.responses
        responses["api.minecraftservices.com/entitlements/mcstore"] = Data(#"{"items":[]}"#.utf8)
        let stub = EndpointHTTPFixture(responses)
        defer { stub.close() }
        let clientID = UUID().uuidString, service = MicrosoftAuth(clientID: clientID, session: stub.session)
        let code = try JSONDecoder().decode(DeviceCode.self, from: Data(#"{"device_code":"device+&=","user_code":"USER","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":1}"#.utf8))
        let (account, credentials) = try await service.finish(code)
        #expect(account.kind == .microsoft && account.username == "Player")
        #expect(credentials.clientID == clientID && credentials.refreshToken == "oauth-refresh")
        let request = try #require(stub.requests.first)
        let form = String(decoding: request.body, as: UTF8.self)
        #expect(form.contains("device_code=device%2B%26%3D") && form.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(!stub.requests.contains { $0.url == AuthenticationEndpoints.license })
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
        #expect(stub.requests.last?.header("Authorization") == "Bearer minecraft-token")
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

    @Test func refreshKeepsThePreviousRefreshTokenWhenNoReplacementIsIssued() async throws {
        var responses = Self.responses
        responses["login.microsoftonline.com/consumers/oauth2/v2.0/token"] = Data(#"{"access_token":"oauth-access"}"#.utf8)
        let stub = EndpointHTTPFixture(responses)
        defer { stub.close() }
        let (account, credentials) = try await MicrosoftAuth(clientID: Self.oldCredentials.clientID, session: stub.session).refresh(Self.oldCredentials, account: Self.account)
        #expect(account.id == Self.account.id && credentials.refreshToken == Self.oldCredentials.refreshToken)
        #expect(credentials.expiresAt > Date().addingTimeInterval(3500))
    }

    private static let account = Account(username: "OldName", uuid: "profile-id", kind: .microsoft)
    private static let oldCredentials = AccountCredentials(accessToken: "old", refreshToken: "old-refresh", expiresAt: .distantPast, clientID: "df01d133-3715-49b0-a48f-31e486c76402")
}
