import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import RuriCore

struct AccountAppearanceTests {
    static let uuid = "0123456789abcdef0123456789abcdef"
    static func png(width: Int = 64, height: Int = 64) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.25, green: 0.5, blue: 1, alpha: 0.75)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage()), output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func microsoftSkinUploadResetAndOwnedCapeSelection() async throws {
        let pixels = try Self.png(), image = try PlayerTextureImage(data: pixels)
        let response = try JSONSerialization.data(withJSONObject: ["id": Self.uuid, "name": "Player", "skins": [
            ["id": "old", "state": "INACTIVE", "variant": "CLASSIC", "url": "https://textures.minecraft.net/texture/old"],
            ["id": "skin", "state": "ACTIVE", "variant": "SLIM", "url": "http://textures.minecraft.net/texture/skin"]],
            "capes": [["id": "cape1", "state": "ACTIVE", "alias": "First Cape", "url": "https://textures.minecraft.net/texture/cape1"],
                      ["id": "cape2", "state": "INACTIVE", "alias": "Second Cape", "url": "https://textures.minecraft.net/texture/cape2"]]])
        let fixture = EndpointHTTPFixture { request in
            if request.url.host == "textures.minecraft.net" { return .init(data: pixels, headers: ["Content-Type": "image/png"]) }
            guard request.url.host == "api.minecraftservices.com" else { return nil }
            return request.method == "GET" ? .init(data: response) : .init(status: 204)
        }
        defer { fixture.close() }
        let account = Account(username: "Player", uuid: Self.uuid, kind: .microsoft)
        let client = AccountAppearanceClient(account: account, accessToken: "microsoft-private-token", session: fixture.session)
        let profile = try await client.load()
        #expect(profile.skin?.id == "skin" && profile.skin?.model == .slim && profile.activeCape?.id == "cape1")
        #expect(profile.uploadable == [.skin] && profile.capes.count == 2)
        let downloaded = try await client.image(for: #require(profile.skin))
        #expect(downloaded.width == 64 && downloaded.height == 64)
        try await client.upload(image, kind: .skin, model: .slim, expecting: profile)
        try await client.reset(.skin, expecting: profile)
        try await client.selectCape("cape2", expecting: profile)
        try await client.reset(.cape, expecting: profile)
        let count = fixture.requests.count
        await #expect(throws: (any Error).self) { try await client.selectCape("not-owned", expecting: profile) }
        await #expect(throws: (any Error).self) { try await client.upload(image, kind: .cape, expecting: profile) }
        #expect(fixture.requests.count == count)
        let api = fixture.requests.filter { $0.url.host == "api.minecraftservices.com" }
        #expect(api.allSatisfy { $0.header("Authorization") == "Bearer microsoft-private-token" })
        #expect(api.map(\.method) == ["GET", "POST", "DELETE", "PUT", "DELETE"])
        #expect(api.map(\.url.path) == ["/minecraft/profile", "/minecraft/profile/skins", "/minecraft/profile/skins/active", "/minecraft/profile/capes/active", "/minecraft/profile/capes/active"])
        let upload = api[1], body = String(decoding: upload.body, as: UTF8.self)
        #expect(upload.header("Content-Type")?.hasPrefix("multipart/form-data; boundary=Ruri-") == true)
        #expect(body.contains("name=\"variant\"\r\n\r\nslim\r\n") && body.contains("filename=\"skin.png\""))
        #expect(upload.body.range(of: image.png) != nil)
        #expect(try JSONDecoder().decode([String: String].self, from: api[3].body) == ["capeId": "cape2"])
        let texture = try #require(fixture.requests.first { $0.url.host == "textures.minecraft.net" })
        #expect(texture.url.scheme == "https" && texture.header("Authorization") == nil)

        let old = try PlayerTextureImage(data: Self.png(height: 32))
        try old.validate(kind: .skin, accountKind: .microsoft)
        #expect(throws: (any Error).self) { try old.validate(kind: .skin, accountKind: .microsoft, model: .slim) }
        let hd = try PlayerTextureImage(data: Self.png(width: 128, height: 128))
        try hd.validate(kind: .skin, accountKind: .external, model: .slim)
        #expect(throws: (any Error).self) { try hd.validate(kind: .skin, accountKind: .microsoft) }
        #expect(throws: (any Error).self) { try PlayerTextureImage(data: Data("not a PNG".utf8)) }
    }

    @Test func externalTexturesRespectProfilePermissionsAndKeepTokenOffImageRequests() async throws {
        let skin = try PlayerTextureImage(data: Self.png()), cape = try PlayerTextureImage(data: Self.png(width: 22, height: 17))
        let payload = try JSONSerialization.data(withJSONObject: ["profileId": Self.uuid, "textures": [
            "SKIN": ["url": "https://images.test/skin.png", "metadata": ["model": "slim"]],
            "CAPE": ["url": "https://images.test/cape.png"]]]).base64EncodedString()
        let response = try JSONSerialization.data(withJSONObject: ["id": Self.uuid, "name": "ExternalPlayer", "properties": [
            ["name": "textures", "value": payload], ["name": "uploadableTextures", "value": "skin, cape"]]])
        let fixture = EndpointHTTPFixture { request in
            if request.url.host == "images.test" { return .init(data: cape.png) }
            guard request.url.host == "skin.test" else { return nil }
            return request.method == "GET" ? .init(data: response) : .init(status: 204)
        }
        defer { fixture.close() }
        var account = Account(username: "ExternalPlayer", uuid: Self.uuid, kind: .external)
        account.externalLogin = .init(server: .init(url: URL(string: "https://skin.test/ygg/")!, name: "Test Site"), username: "external-account")
        let client = AccountAppearanceClient(account: account, accessToken: "external-private-token", session: fixture.session)
        let profile = try await client.load()
        #expect(profile.skin?.model == .slim && profile.activeCape != nil && profile.uploadable == [.skin, .cape])
        _ = try await client.image(for: #require(profile.activeCape))
        try await client.upload(skin, kind: .skin, model: .classic, expecting: profile)
        try await client.upload(cape, kind: .cape, expecting: profile)
        try await client.reset(.skin, expecting: profile)
        try await client.reset(.cape, expecting: profile)
        let requests = fixture.requests, mutations = requests.filter { $0.method != "GET" }
        #expect(requests.first?.url.path == "/ygg/sessionserver/session/minecraft/profile/" + Self.uuid)
        #expect(requests.filter { $0.method == "GET" }.allSatisfy { $0.header("Authorization") == nil })
        #expect(mutations.allSatisfy { $0.header("Authorization") == "Bearer external-private-token" })
        #expect(mutations.map(\.method) == ["PUT", "PUT", "DELETE", "DELETE"])
        #expect(mutations.map(\.url.path) == ["skin", "cape", "skin", "cape"].map { "/ygg/api/user/profile/\(Self.uuid)/\($0)" })
        #expect(String(decoding: mutations[0].body, as: UTF8.self).contains("name=\"model\"\r\n\r\n\r\n"))
        #expect(!String(decoding: mutations[1].body, as: UTF8.self).contains("name=\"model\""))

        let denied = AccountAppearance(account: account, playerName: "ExternalPlayer", skin: profile.skin, capes: profile.capes, uploadable: [])
        await #expect(throws: (any Error).self) { try await client.upload(skin, kind: .skin, expecting: denied) }
        await #expect(throws: (any Error).self) { try await client.reset(.cape, expecting: denied) }
        #expect(fixture.requests.count == requests.count)
        let otherAccount = Account(username: "Other", uuid: Self.uuid, kind: .microsoft)
        let other = AccountAppearance(account: otherAccount, playerName: "Other", skin: nil, capes: [], uploadable: [.skin])
        await #expect(throws: (any Error).self) { try await client.upload(skin, kind: .skin, expecting: other) }

        let wrong = EndpointHTTPFixture(["skin.test/ygg/sessionserver/session/minecraft/profile/" + Self.uuid: Data(#"{"id":"ffffffffffffffffffffffffffffffff","name":"Wrong","properties":[]}"#.utf8)])
        defer { wrong.close() }
        await #expect(throws: (any Error).self) { try await AccountAppearanceClient(account: account, accessToken: "external-private-token", session: wrong.session).load() }
    }
}

extension AccountAppearanceTests {
    @Test func expiredLoginIsDistinguishableAndOversizedResponsesAreRejected() async throws {
        let account = Account(username: "Player", uuid: Self.uuid, kind: .microsoft)
        let expired = EndpointHTTPFixture { _ in .init(status: 401) }; defer { expired.close() }
        await #expect(throws: AccountAppearanceError.loginExpired) {
            try await AccountAppearanceClient(account: account, accessToken: "old-token", session: expired.session).load()
        }
        let large = EndpointHTTPFixture { _ in .init(data: Data(repeating: 65, count: 262_145)) }; defer { large.close() }
        await #expect(throws: (any Error).self) {
            try await AccountAppearanceClient(account: account, accessToken: "token", session: large.session).load()
        }
        let png = try Self.png()
        let image = EndpointHTTPFixture { _ in .init(data: png, headers: ["Content-Length": "999999999", "Content-Type": "image/png"]) }; defer { image.close() }
        let client = AccountAppearanceClient(account: account, accessToken: "secret", session: image.session)
        await #expect(throws: (any Error).self) { try await client.image(for: AccountTexture(id: "skin", name: "Skin", url: URL(string: "https://images.test/skin.png?signature=test")!, active: true, model: .classic)) }
        #expect(image.requests.first?.header("Authorization") == nil)
    }
}
