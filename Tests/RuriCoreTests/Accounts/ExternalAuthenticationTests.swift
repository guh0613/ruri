import Foundation
import CryptoKit
import Testing
@testable import RuriCore

struct ExternalAuthenticationTests {
    static let first = "0123456789abcdef0123456789abcdef"
    static let second = "fedcba9876543210fedcba9876543210"
    static let metadata = Data(#"{"meta":{"serverName":"Test Skin Site"},"skinDomains":["skin.test"],"signaturePublickey":"-----BEGIN PUBLIC KEY-----\nfixture\n-----END PUBLIC KEY-----"}"#.utf8)

    @Test func discoverySelectionRefreshAndAccountPersistence() async throws {
        let fixture = EndpointHTTPFixture { request in
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            switch request.url.path {
            case "/": return .init(headers: ["X-Authlib-Injector-API-Location": "/api/yggdrasil/"])
            case "/api/yggdrasil": return .init(data: Self.metadata)
            case "/api/yggdrasil/authserver/authenticate":
                if body["password"] as? String == "wrong-secret" { return .init(data: Data(#"{"errorMessage":"wrong-secret"}"#.utf8), status: 403) }
                return .init(data: try! JSONSerialization.data(withJSONObject: ["accessToken": "pending-token", "clientToken": body["clientToken"]!,
                    "availableProfiles": [["id": Self.first, "name": "First"], ["id": Self.second, "name": "Second"]]]))
            case "/api/yggdrasil/authserver/refresh":
                let choosing = body["selectedProfile"] != nil
                return .init(data: try! JSONSerialization.data(withJSONObject: ["accessToken": choosing ? "selected-token" : "refreshed-token", "clientToken": body["clientToken"]!,
                    "selectedProfile": ["id": Self.second, "name": choosing ? "Second" : "Renamed"],
                    "user": ["id": Self.first, "properties": [["name": "preferredLanguage", "value": "zh_CN"]]]]))
            case "/api/yggdrasil/authserver/validate": return .init(status: body["accessToken"] as? String == "refreshed-token" ? 204 : 403)
            case "/api/yggdrasil/authserver/invalidate": return .init(status: 204)
            default: return nil
            }
        }
        defer { fixture.close() }
        let auth = ExternalAuthentication(session: fixture.session)
        let metadata = try await auth.discover("skin.test")
        #expect(metadata.server.url.absoluteString == "https://skin.test/api/yggdrasil/")
        let login = try await auth.login(server: metadata.server, username: "player@example.test", password: "login-secret")
        let selected = try await auth.select(try #require(login.availableProfiles?.last), from: login, server: metadata.server)
        let original = try selected.account(server: metadata.server, username: "player@example.test")
        #expect(original.username == "Second" && original.uuid == Self.second)
        let (updated, credentials) = try await auth.refresh(account: original, credentials: selected.credentials)
        #expect(updated.id == original.id && updated.uuid == Self.second && updated.username == "Renamed")
        #expect(credentials.accessToken == "refreshed-token" && credentials.user?.propertiesJSON.contains("zh_CN") == true)
        let count = fixture.requests.count
        let (valid, _) = try await auth.refresh(account: updated, credentials: credentials)
        #expect(valid == updated && fixture.requests.count == count + 1)
        try await auth.invalidate(server: metadata.server, credentials: credentials)

        #expect(fixture.requests.filter { $0.method == "POST" }.allSatisfy { $0.url.host == "skin.test" && $0.header("Content-Type")?.hasPrefix("application/json") == true })
        do {
            _ = try await auth.login(server: metadata.server, username: "player@example.test", password: "wrong-secret")
            Issue.record("Wrong credentials unexpectedly accepted")
        } catch { #expect(!error.localizedDescription.contains("wrong-secret")) }

        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var state = PersistentState(); state.accounts = [try Account(username: "Offline"), updated]; state.activeAccountID = updated.id
        try StateStore.save(state, to: paths)
        let saved = try StateStore.load(paths)
        #expect(saved.accounts == state.accounts && saved.activeAccountID == updated.id)
        let json = try String(contentsOf: paths.state, encoding: .utf8)
        #expect(!json.contains("token") && !json.contains("secret") && !json.contains("clientToken"))
        #expect(throws: (any Error).self) { try ExternalAuthServer.address("http://skin.test") }
        #expect(throws: (any Error).self) { try ExternalAuthServer.address("https://user:password@skin.test") }
        #expect(try ExternalAuthServer.address("authlib-injector:yggdrasil-server:https%3A%2F%2Fskin.test%2F") == URL(string: "https://skin.test/"))
    }

    @Test func verifiedInjectorCacheAndLaunchArguments() async throws {
        let artifact = Data("fixture jar".utf8)
        let digest = SHA256.hash(data: artifact).map { String(format: "%02x", $0) }.joined()
        let release = try JSONSerialization.data(withJSONObject: ["build_number": 123, "version": "fixture", "download_url": "https://artifact.test/injector.jar", "checksums": ["sha256": digest]])
        let fixture = EndpointHTTPFixture(["authlib-injector.yushi.moe/artifact/latest.json": release, "artifact.test/injector.jar": artifact])
        defer { fixture.close() }
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = AuthlibInjector(http: HTTPClient(session: fixture.session, routing: NetworkRouting(source: .official)))
        let jar = try await service.prepare(paths: paths)
        #expect(try Data(contentsOf: jar) == artifact)
        #expect(try await service.prepare(paths: paths) == jar && fixture.requests.count == 2)
        try Data("corrupted".utf8).write(to: jar)
        _ = try await service.prepare(paths: paths)
        #expect(try Data(contentsOf: jar) == artifact)

        let instance = GameInstance(name: "External", gameVersion: "1.0")
        let gameJar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: gameJar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: gameJar)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1.0","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name} --uuid ${auth_uuid} --session ${auth_session} --accessToken ${auth_access_token} --userType ${user_type} --userProperties ${user_properties}","javaVersion":{"majorVersion":8}}"#.utf8))
        let java = JavaRuntime(path: "/test/java", version: "8", major: 8, architecture: "x86_64", vendor: "Test")
        let server = ExternalAuthServer(url: URL(string: "https://skin.test/api/yggdrasil/")!, name: "Skin Site")
        var account = Account(username: "Player", uuid: Self.second, kind: .external)
        account.externalLogin = .init(server: server, username: "player@example.test")
        let prepared = ExternalAuthLaunch(jar: jar, metadata: .init(server: server, data: Self.metadata), userProperties: #"{"preferredLanguage":["zh_CN"]}"#)
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: "access-secret", paths: paths, externalAuth: prepared)
        let main = try #require(plan.arguments.firstIndex(of: "Main")), agent = try #require(plan.arguments.firstIndex(where: { $0.hasPrefix("-javaagent:") }))
        #expect(agent < main && plan.arguments[agent] == "-javaagent:\(jar.path)=https://skin.test/api/yggdrasil/")
        func argument(_ name: String) -> String? { plan.arguments.firstIndex(of: name).map { plan.arguments[$0 + 1] } }
        #expect(argument("--userType") == "mojang" && argument("--session") == "access-secret")
        #expect(argument("--uuid") == Self.second && argument("--userProperties") == prepared.userProperties)
        #expect(!plan.redactedCommand.contains("access-secret") && !plan.redactedCommand.contains("zh_CN") && !plan.redactedCommand.contains(Self.metadata.base64EncodedString()))
        #expect(throws: (any Error).self) { try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths) }

        let badFixture = EndpointHTTPFixture(["authlib-injector.yushi.moe/artifact/latest.json": release, "artifact.test/injector.jar": Data("bad download".utf8)])
        defer { badFixture.close() }
        try Data("corrupted".utf8).write(to: jar)
        let badService = AuthlibInjector(http: HTTPClient(session: badFixture.session, routing: NetworkRouting(source: .official)))
        await #expect(throws: (any Error).self) { try await badService.prepare(paths: paths) }
        #expect(try Data(contentsOf: jar) == Data("corrupted".utf8))
    }
}
