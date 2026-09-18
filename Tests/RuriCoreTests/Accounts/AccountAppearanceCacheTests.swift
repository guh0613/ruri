import Foundation
import Testing
@testable import RuriCore

@MainActor struct AccountAppearanceCacheTests {
    private let account = Account(username: "Player", uuid: AccountAppearanceTests.uuid, kind: .microsoft)
    private let skin = AccountTexture(id: "skin", name: "Skin", url: URL(string: "https://textures.minecraft.net/texture/skin")!, active: true, model: .slim)
    private let cape = AccountTexture(id: "cape", name: "Cape", url: URL(string: "https://textures.minecraft.net/texture/cape")!, active: true, model: .classic)

    private func workspace() throws -> LauncherPaths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-appearance-cache-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return LauncherPaths(root: root)
    }

    @Test func profilesAreSessionOnlyWhileImagesSurviveRestart() throws {
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        let appearance = AccountAppearance(account: account, playerName: "Player", skin: skin, capes: [cape], uploadable: [.skin])
        cache.save(appearance)
        let loaded = try #require(cache.appearance(for: account))
        #expect(loaded.skin == skin && loaded.capes == [cape] && loaded.uploadable == [.skin])
        var differentIdentity = account; differentIdentity.uuid = String(repeating: "f", count: 32)
        #expect(cache.appearance(for: differentIdentity) == nil)
        let image = try PlayerTextureImage(data: AccountAppearanceTests.png())
        try cache.save(image, for: skin, kind: .skin, account: account)

        let reopened = AccountAppearanceCache(paths: paths)
        #expect(reopened.appearance(for: account) == nil)
        #expect(try reopened.image(for: skin, kind: .skin, account: account)?.png == image.png)
        #expect(!FileManager.default.fileExists(atPath: paths.root.appendingPathComponent("appearance/remote/\(account.id)/profile.json").path))

        let changed = AccountTexture(id: "new", name: "New skin", url: URL(string: "https://textures.minecraft.net/texture/new")!, active: true, model: .classic)
        reopened.save(AccountAppearance(account: account, playerName: "Player", skin: changed, capes: [cape], uploadable: [.skin]))
        #expect(reopened.appearance(for: account)?.skin == changed)
        #expect(try reopened.image(for: changed, kind: .skin, account: account) == nil)
    }

    @Test func defaultAppearanceIsACacheHitAndInvalidationPreservesReusableImages() throws {
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        let image = try PlayerTextureImage(data: AccountAppearanceTests.png())
        try cache.save(image, for: skin, kind: .skin, account: account)
        cache.save(AccountAppearance(account: account, playerName: "Player", skin: nil, capes: [], uploadable: [.skin]))
        let loaded = try #require(cache.appearance(for: account))
        #expect(loaded.skin == nil && loaded.activeCape == nil)
        cache.invalidateAppearance(for: account)
        #expect(cache.appearance(for: account) == nil)
        #expect(try cache.image(for: skin, kind: .skin, account: account)?.png == image.png)
        try cache.remove(for: account)
        #expect(try cache.image(for: skin, kind: .skin, account: account) == nil)
    }

    @Test func texturesAreReusedByURLAndUploadsCanInvalidateUnchangedURLs() throws {
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        let image = try PlayerTextureImage(data: AccountAppearanceTests.png())
        let capeImage = try PlayerTextureImage(data: AccountAppearanceTests.png(height: 32))
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
        let paths = try workspace(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let cache = AccountAppearanceCache(paths: paths)
        let legacy = try PlayerTextureImage(data: AccountAppearanceTests.png(height: 32))
        let classic = AccountTexture(id: skin.id, name: skin.name, url: skin.url, active: true, model: .classic)
        try cache.save(legacy, for: classic, kind: .skin, account: account)
        #expect(throws: (any Error).self) { try cache.image(for: skin, kind: .skin, account: account) }
    }

    @Test func cacheCannotEscapeThroughSymlinks() throws {
        let paths = try workspace(), outside = try workspace()
        defer { try? FileManager.default.removeItem(at: paths.root); try? FileManager.default.removeItem(at: outside.root) }
        let root = paths.root.appendingPathComponent("appearance/remote")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(account.id.uuidString), withDestinationURL: outside.root)
        let cache = AccountAppearanceCache(paths: paths)
        let image = try PlayerTextureImage(data: AccountAppearanceTests.png())
        #expect(throws: (any Error).self) {
            try cache.save(image, for: skin, kind: .skin, account: account)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.root.path).isEmpty)
    }
}
