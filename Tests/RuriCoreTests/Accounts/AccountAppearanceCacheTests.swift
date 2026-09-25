import Foundation
import Testing
@testable import RuriCore

@MainActor struct AccountAppearanceCacheTests {
    private let account = Account(username: "Player", uuid: AccountTestFixtures.uuid, kind: .microsoft)
    private let skin = AccountTexture(id: "skin", name: "Skin", url: URL(string: "https://textures.minecraft.net/texture/skin")!, active: true, model: .slim)
    private let cape = AccountTexture(id: "cape", name: "Cape", url: URL(string: "https://textures.minecraft.net/texture/cape")!, active: true, model: .classic)

    @Test func profilesExpireWhileImagesSurviveRestartAndProfileInvalidation() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        cache.save(AccountAppearance(account: account, playerName: "Player", skin: nil, capes: [], uploadable: [.skin]))
        #expect(cache.appearance(for: account) != nil)
        var differentIdentity = account; differentIdentity.uuid = String(repeating: "f", count: 32)
        #expect(cache.appearance(for: differentIdentity) == nil)
        let image = try PlayerTextureImage(data: AccountTestFixtures.png())
        try cache.save(image, for: skin, kind: .skin, account: account)
        cache.invalidateAppearance(for: account)
        #expect(cache.appearance(for: account) == nil)
        #expect(try cache.image(for: skin, kind: .skin, account: account)?.png == image.png)
        cache.save(AccountAppearance(account: account, playerName: "Player", skin: skin, capes: [cape], uploadable: [.skin]))

        let reopened = AccountAppearanceCache(paths: paths)
        #expect(reopened.appearance(for: account) == nil)
        #expect(try reopened.image(for: skin, kind: .skin, account: account)?.png == image.png)
        try reopened.remove(for: account)
        #expect(try reopened.image(for: skin, kind: .skin, account: account) == nil)
    }

    @Test func texturesAreReusedByURLAndUploadsCanInvalidateUnchangedURLs() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        let image = try PlayerTextureImage(data: AccountTestFixtures.png())
        let capeImage = try PlayerTextureImage(data: AccountTestFixtures.png(height: 32))
        try cache.save(image, for: skin, kind: .skin, account: account)
        try cache.save(capeImage, for: cape, kind: .cape, account: account)
        let reopened = AccountAppearanceCache(paths: paths)
        let renamed = AccountTexture(id: "new-id", name: "New name", url: skin.url, active: false, model: .classic)
        #expect(try reopened.image(for: renamed, kind: .skin, account: account)?.png == image.png)
        let changed = AccountTexture(id: skin.id, name: skin.name, url: URL(string: "https://textures.minecraft.net/texture/new")!, active: true, model: skin.model)
        #expect(try reopened.image(for: changed, kind: .skin, account: account) == nil)
        var other = account; other.id = UUID()
        #expect(try reopened.image(for: skin, kind: .skin, account: other) == nil)
        try reopened.invalidateImage(for: skin, kind: .skin, account: account)
        #expect(try reopened.image(for: skin, kind: .skin, account: account) == nil)
        #expect(try reopened.image(for: cape, kind: .cape, account: account)?.png == capeImage.png)
    }

    @Test func cachedPixelsStillRespectTheRequestedModel() throws {
        let paths = try AccountTestFixtures.paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        let legacy = try PlayerTextureImage(data: AccountTestFixtures.png(height: 32))
        let classic = AccountTexture(id: skin.id, name: skin.name, url: skin.url, active: true, model: .classic)
        try cache.save(legacy, for: classic, kind: .skin, account: account)
        #expect(throws: (any Error).self) { try cache.image(for: skin, kind: .skin, account: account) }
    }

    @Test func cacheCannotEscapeThroughSymlinks() throws {
        let paths = try AccountTestFixtures.paths(), outside = try AccountTestFixtures.paths()
        defer { try? FileManager.default.removeItem(at: paths.root); try? FileManager.default.removeItem(at: outside.root) }
        let root = paths.root.appendingPathComponent("appearance/remote")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(account.id.uuidString), withDestinationURL: outside.root)
        let cache = AccountAppearanceCache(paths: paths)
        let image = try PlayerTextureImage(data: AccountTestFixtures.png())
        #expect(throws: (any Error).self) {
            try cache.save(image, for: skin, kind: .skin, account: account)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path).isEmpty)
    }
}
