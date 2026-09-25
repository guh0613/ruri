import Foundation
import Testing
import Security
@testable import RuriCore

struct OfflineSkinTests {
    func fixture() throws -> (LauncherPaths, OfflineSkinLaunch) {
        let paths = try AccountTestFixtures.paths()
        let jar = paths.root.appendingPathComponent("injector.jar"); try Data().write(to: jar)
        let image = try PlayerTextureImage(data: AccountTestFixtures.png())
        return (paths, try OfflineSkinLaunch(account: Account(username: "OfflineSkin"), skin: SavedPlayerSkin(name: "Skin", image: image, model: .slim), injector: jar))
    }
    @Test(.timeLimit(.minutes(1))) @MainActor func loopbackServiceReturnsSignedProfileAndExactPixelsAndStops() async throws {
        let (paths, launch) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let server = try await OfflineSkinServer.start(launch)
        defer { server.stop() }
        let root = try #require(server.root)
        #expect(root.host == "127.0.0.1" && root.port != nil)
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let (metadata, _) = try await session.data(from: root)
        let json = try #require(try JSONSerialization.jsonObject(with: metadata) as? [String: Any])
        let (profileData, _) = try await session.data(from: root.appendingPathComponent("sessionserver/session/minecraft/profile/" + launch.account.uuid))
        let profile = try #require(try JSONSerialization.jsonObject(with: profileData) as? [String: Any])
        #expect(profile["id"] as? String == launch.account.uuid)
        let property = try #require((profile["properties"] as? [[String: String]])?.first)
        let value = try #require(property["value"]), signature = try #require(property["signature"].flatMap { Data(base64Encoded: $0) })
        let payloadData = try #require(Data(base64Encoded: value))
        let payload = try #require(try JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        let texture = try #require((payload["textures"] as? [String: [String: Any]])?["SKIN"])
        #expect((texture["metadata"] as? [String: String])?["model"] == "slim")
        let url = try #require((texture["url"] as? String).flatMap(URL.init(string:)))
        let (pixels, textureResponse) = try await session.data(from: url)
        #expect(pixels == launch.skin?.png && (textureResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "image/png")
        let pem = try #require(json["signaturePublickey"] as? String)
        let encoded = pem.components(separatedBy: .newlines).filter { !$0.hasPrefix("---") }.joined()
        let publicData = try #require(Data(base64Encoded: encoded))
        let key = try #require(SecKeyCreateWithData(publicData as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil))
        #expect(SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA1, Data(value.utf8) as CFData, signature as CFData, nil))
        let (_, missing) = try await session.data(from: root.appendingPathComponent("sessionserver/session/minecraft/profile/" + String(repeating: "f", count: 32)))
        #expect((missing as? HTTPURLResponse)?.statusCode == 404)
        let (_, outside) = try await session.data(from: URL(string: "http://127.0.0.1:\(try #require(root.port))/")!)
        #expect((outside as? HTTPURLResponse)?.statusCode == 404)
        server.stop()
        var request = URLRequest(url: root); request.timeoutInterval = 1
        await #expect(throws: (any Error).self) { try await session.data(for: request) }
    }
    @Test(.timeLimit(.minutes(1))) @MainActor func lookupAndLaunchInjectionRespectOfflineIdentity() async throws {
        let (paths, input) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Offline", gameVersion: "1.0")
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: jar)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1.0","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name} --uuid ${auth_uuid} --accessToken ${auth_access_token} --userType ${user_type}","javaVersion":{"majorVersion":8}}"#.utf8))
        let java = JavaRuntime(path: "/test/java", version: "8", major: 8, architecture: "x86_64", vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: input.account, accessToken: "offline-token", paths: paths, offlineSkin: input)
        let launch = try #require(plan.offlineSkin)
        let server = try await OfflineSkinServer.start(launch); defer { server.stop() }
        let final = try server.applying(to: plan)
        let index = try #require(final.arguments.firstIndex(where: { $0.hasPrefix("-javaagent:") }))
        #expect(index < (try #require(final.arguments.firstIndex(of: "Main"))))
        #expect(final.arguments.contains("-Dauthlibinjector.side=client") && final.offlineSkin == nil)
        #expect(final.arguments[try #require(final.arguments.firstIndex(of: "--uuid")) + 1] == input.account.uuid)
        #expect(final.arguments[try #require(final.arguments.firstIndex(of: "--userType")) + 1] == "msa")
        #expect(!final.redactedCommand.contains("offline-token") && !final.redactedCommand.contains(server.metadata.base64EncodedString()))
        var request = URLRequest(url: try #require(server.root).appendingPathComponent("api/profiles/minecraft"))
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(["offlineskin", "SomeoneElse"])
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(for: request)
        #expect(try JSONDecoder().decode([[String: String]].self, from: data) == [["id": input.account.uuid, "name": input.account.username]])
        #expect(throws: (any Error).self) { try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Another"), paths: paths, offlineSkin: input) }
    }
    @Test func hdSkinIsNormalizedWithoutChangingTheSavedOriginal() throws {
        let (paths, fixture) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let image = try PlayerTextureImage(data: AccountTestFixtures.png(width: 256, height: 256))
        let original = try SavedPlayerSkin(name: "HD", image: image, model: .slim)
        let launch = try OfflineSkinLaunch(account: fixture.account, skin: original, injector: fixture.injector)
        #expect(try launch.skin?.image.width == 64 && launch.skin?.image.height == 64)
        #expect(try original.image.width == 256)
    }
}

extension OfflineSkinTests {
    @Test(.timeLimit(.minutes(1))) @MainActor func capeOnlyAppearanceWorksAndCompactCapeIsPadded() async throws {
        let (paths, fixture) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cape = try PlayerTextureImage(data: AccountTestFixtures.png(width: 22, height: 17))
        let launch = try OfflineSkinLaunch(account: fixture.account, skin: nil, cape: cape, injector: fixture.injector)
        let normalized = try PlayerTextureImage(data: #require(launch.capePNG))
        #expect(normalized.width == 64 && normalized.height == 32 && launch.skin == nil)
        let server = try await OfflineSkinServer.start(launch); defer { server.stop() }
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(from: #require(server.root).appendingPathComponent("sessionserver/session/minecraft/profile/" + fixture.account.uuid))
        let profile = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let property = try #require((profile["properties"] as? [[String: String]])?.first?["value"])
        let decoded = try #require(Data(base64Encoded: property))
        let payload = try #require(try JSONSerialization.jsonObject(with: decoded) as? [String: Any])
        let textures = try #require(payload["textures"] as? [String: Any])
        #expect(textures["CAPE"] != nil && textures["SKIN"] == nil)
        let store = SkinLibrary(paths: paths)
        try store.setCape(cape, for: fixture.account.id)
        #expect(try store.cape(for: fixture.account.id)?.png == cape.png)
        try store.setPreview(fixture.skin, for: fixture.account.id)
        try store.setPreview(nil, for: fixture.account.id)
        #expect(try store.cape(for: fixture.account.id) != nil)
        try store.setCape(nil, for: fixture.account.id)
        #expect(try store.cape(for: fixture.account.id) == nil)
    }
}
