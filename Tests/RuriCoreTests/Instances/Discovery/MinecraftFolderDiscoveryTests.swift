import Foundation
import Testing
@testable import RuriCore

struct MinecraftFolderDiscoveryTests {
    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-folder-discovery-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func repository(_ path: String, in root: URL) throws -> URL {
        let folder = root.appendingPathComponent(path)
        let version = folder.appendingPathComponent("versions/1.21.1")
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
        try Data(#"{"id":"1.21.1","libraries":[]}"#.utf8).write(to: version.appendingPathComponent("1.21.1.json"))
        return folder
    }

    @Test func findsHiddenGameFolderFromLauncherWithoutWriting() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let game = try repository("HMCL/.minecraft", in: root)
        try Data().write(to: root.appendingPathComponent("HMCL/launcher.jar"))
        let before = try FileTreeManifest.capture(in: root)
        let previews = try MinecraftFolderDiscovery.inspect(root.appendingPathComponent("HMCL"))
        #expect(previews.map { $0.directory.path } == [game.path])
        #expect(previews.first?.versionNames == ["1.21.1"])
        try before.requireMatch(in: root)
    }

    @Test func offersMultipleNearbyRepositoriesAndIgnoresDeeperTrees() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try repository("A/.minecraft", in: root)
        let second = try repository("B/minecraft", in: root)
        _ = try repository("nested/deeper/C/.minecraft", in: root)
        let previews = try MinecraftFolderDiscovery.inspect(root)
        #expect(Set(previews.map { $0.directory.path }) == Set([first.path, second.path]))
    }

    @Test func unrelatedNonemptyFolderIsRejectedWithoutCreatingMetadata() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("personal files".utf8).write(to: root.appendingPathComponent("notes.txt"))
        #expect(throws: (any Error).self) { try MinecraftFolderDiscovery.inspect(root) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".ruri-directory.json").path))
    }

    @Test func symbolicLinksAreNotTraversed() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let game = try repository("Outside", in: root)
        let launcher = root.appendingPathComponent("Launcher")
        try FileManager.default.createDirectory(at: launcher, withIntermediateDirectories: true)
        let link = launcher.appendingPathComponent(".minecraft")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: game)
        #expect(throws: (any Error).self) { try MinecraftFolderDiscovery.inspect(launcher) }
        #expect(throws: (any Error).self) { try MinecraftFolderDiscovery.inspect(link) }
    }

    @Test func freshDiscoveryFindsStandardAndPortableLocationsWithoutHistory() throws {
        let home = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: home) }
        let support = home.appendingPathComponent("Library/Application Support")
        let official = try repository("Library/Application Support/minecraft", in: home)
        let hidden = try repository("Library/Application Support/.minecraft", in: home)
        let portable = try repository("CustomLauncher/.minecraft", in: home)
        let dotHome = try repository(".minecraft", in: home)
        let before = try FileTreeManifest.capture(in: home)
        let found = try MinecraftFolderDiscovery.commonLocations(home: home, applicationSupport: [support, support])
        #expect(Set(found.map(\.path)) == Set([official.path, hidden.path, portable.path, dotHome.path]))
        #expect(found.count == 4)
        try before.requireMatch(in: home)
    }

    @Test func automaticDiscoverySkipsProtectedDeepHiddenAndPackageLocations() throws {
        let home = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: home) }
        for path in ["Desktop", "Documents", "Downloads", "Pictures", "Music", "Movies", "Library/UnknownApp", ".private", "Launcher.app", "Games/DeepLauncher"] {
            _ = try repository(path + "/.minecraft", in: home)
        }
        let support = home.appendingPathComponent("Library/Application Support")
        #expect(try MinecraftFolderDiscovery.commonLocations(home: home, applicationSupport: [support]).isEmpty)
        // Explicit selection still discovers games within those locations.
        #expect(try MinecraftFolderDiscovery.inspect(home.appendingPathComponent("Desktop")).count == 1)
    }

    @Test func automaticDiscoveryDoesNotFollowSymlinksOrOfferUnsupportedInstanceLayouts() throws {
        let home = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: home) }
        let external = try repository(".private/Game", in: home)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("LinkedLauncher"), withDestinationURL: external.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: home.appendingPathComponent("Launcher"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: home.appendingPathComponent("Launcher/.minecraft"), withDestinationURL: external)
        // Prism/ATLauncher-style game data is not a versions repository.
        try FileManager.default.createDirectory(at: home.appendingPathComponent("PrismInstance/minecraft/saves"), withIntermediateDirectories: true)
        #expect(try MinecraftFolderDiscovery.commonLocations(home: home, applicationSupport: []).isEmpty)
    }

    @Test func currentRegistrationsOverrideCachedDiscoveryWithoutDuplicates() {
        let active = GameDirectory(id: UUID(), name: "Renamed", url: URL(fileURLWithPath: "/fixture/Active"), bookmark: nil, createdAt: Date())
        let removed = GameDirectory(id: UUID(), name: "Modpacks", url: URL(fileURLWithPath: "/fixture/Removed"), bookmark: nil, createdAt: Date())
        let discovered = URL(fileURLWithPath: "/fixture/New")
        let suggestions = MinecraftFolderDiscovery.suggestions(locations: [active.url, discovered], directories: [active], removedDirectories: [removed])
        #expect(suggestions.count == 3)
        #expect(suggestions.first { $0.directory == active.url }?.name == "Renamed")
        #expect(suggestions.first { $0.directory == active.url }?.status == .added)
        #expect(suggestions.first { $0.directory == removed.url }?.status == .removed)
        #expect(suggestions.first { $0.directory == discovered }?.status == .detected)
    }

    @Test func unavailableRecordedFolderRemainsVisibleWithoutClaimingReplacement() throws {
        let home = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: home) }
        let root = try repository("Game", in: home)
        let paths = LauncherPaths(root: home.appendingPathComponent("Ruri"))
        let added = try MinecraftFolderStore.add(name: "Retained", url: root, paths: paths)
        let detached = try GameDirectoryStore.remove(try #require(added.selectedDirectoryID), paths: paths)
        try FileManager.default.moveItem(at: root, to: home.appendingPathComponent("Moved"))
        let records = (detached.detachedMinecraftFolders ?? []).map(\.directory)
        let missing = MinecraftFolderDiscovery.suggestions(locations: [], directories: [], removedDirectories: records)
        #expect(missing.count == 1 && missing.first?.status == .removed)
        #expect(missing.first?.name == "Retained")
        // An unrelated repository at the old path must not inherit its settings.
        _ = try repository("Game", in: home)
        let result = try #require(MinecraftFolderDiscovery.suggestions(locations: [root], directories: [], removedDirectories: records).first)
        let registration = try #require(result.registration)
        #expect(throws: (any Error).self) { try registration.validateAvailability() }
    }
}
