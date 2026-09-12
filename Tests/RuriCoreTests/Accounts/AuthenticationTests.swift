import Foundation
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

    @Test func configuredSessionExercisesOfficialAuthenticationExchange() async throws {
        let stub = EndpointHTTPFixture([
            "login.microsoftonline.com/consumers/oauth2/v2.0/devicecode": Data(#"{"device_code":"device","user_code":"USER","verification_uri":"https://www.microsoft.com/link","expires_in":900}"#.utf8),
            "login.microsoftonline.com/consumers/oauth2/v2.0/token": Data(#"{"access_token":"oauth-access","refresh_token":"oauth-refresh"}"#.utf8),
            "user.auth.xboxlive.com/user/authenticate": Data(#"{"Token":"xbox-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "xsts.auth.xboxlive.com/xsts/authorize": Data(#"{"Token":"xsts-token","DisplayClaims":{"xui":[{"uhs":"user-hash"}]}}"#.utf8),
            "api.minecraftservices.com/authentication/login_with_xbox": Data(#"{"access_token":"minecraft-token","expires_in":3600}"#.utf8),
            "api.minecraftservices.com/entitlements/mcstore": Data(#"{"items":[{"name":"game_minecraft"}]}"#.utf8),
            "api.minecraftservices.com/minecraft/profile": Data(#"{"id":"profile-id","name":"Player"}"#.utf8)
        ])
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
}
