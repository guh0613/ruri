import Foundation
import Testing
@testable import RuriCore

struct WorldQuickPlayTests {
    private func manifest() throws -> VersionManifest {
        try JSONDecoder().decode(VersionManifest.self, from: Data(#"""
        {"id":"1.21.1","mainClass":"Main","libraries":[],"javaVersion":{"majorVersion":21},
         "arguments":{"game":["--gameDir","${game_directory}",
           {"rules":[{"action":"allow","features":{"has_quick_plays_support":true}}],"value":["--quickPlayPath","${quickPlayPath}"]},
           {"rules":[{"action":"allow","features":{"is_quick_play_singleplayer":true}}],"value":["--quickPlaySingleplayer","${quickPlaySingleplayer}"]},
           {"rules":[{"action":"allow","features":{"is_quick_play_multiplayer":true}}],"value":["--quickPlayMultiplayer","${quickPlayMultiplayer}"]}]}}
        """#.utf8))
    }

    @Test func clickedWorldReplacesOldDestinationForOneLaunch() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-quick-play-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = GameInstance(name: "Worlds", gameVersion: "1.21.1")
        instance.extraGameArguments = "--quickPlaySingleplayer=Old --quickPlayMultiplayer example.test --server old.test --port 25565"
        var state = PersistentState(); state.instances = [instance]; try StateStore.save(state, to: paths)
        let folder = "我的世界 🐱", worldURL = paths.game(instance.id).appendingPathComponent("saves/\(folder)")
        try FileManager.default.createDirectory(at: worldURL, withIntermediateDirectories: true)
        try WorldTests().nbt().write(to: worldURL.appendingPathComponent("level.dat"))
        let jar = paths.versions.appendingPathComponent("1.21.1/1.21.1.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: jar)
        let manifest = try manifest(), world = try WorldQuickPlay.selection(folder: folder, instanceID: instance.id, paths: paths)
        let java = JavaRuntime(path: "/test/java", version: "21", major: 21, architecture: GameInstaller.architecture(for: manifest), vendor: "Test")
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths, world: world)
        let index = try #require(plan.arguments.firstIndex(of: "--quickPlaySingleplayer"))
        #expect(plan.arguments[index + 1] == folder)
        #expect(plan.arguments.filter { $0 == "--quickPlaySingleplayer" }.count == 1)
        #expect(plan.arguments.filter { $0 == "--gameDir" }.count == 1)
        #expect(!plan.arguments.contains("--quickPlayMultiplayer") && !plan.arguments.contains("--server") && !plan.arguments.contains("--quickPlaySingleplayer=Old"))
        #expect(try StateStore.load(paths).instances[0].extraGameArguments == instance.extraGameArguments)
        instance.extraGameArguments = nil
        let normal = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        #expect(!normal.arguments.contains { $0.hasPrefix("--quickPlay") })
    }

    @Test func unsupportedVersionAndMissingWorldCannotQuickPlay() throws {
        var manifest = try manifest(); manifest.arguments = nil
        let old = GameInstance(name: "Old", gameVersion: "1.19.4")
        #expect(throws: (any Error).self) { try WorldQuickPlay.requireSupport(instance: old, manifest: manifest) }
        #expect(WorldQuickPlay.supports(instance: GameInstance(name: "Supported", gameVersion: "1.20"), manifest: manifest))
        let (paths, id, _, worldURL) = try WorldTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(throws: (any Error).self) { try WorldQuickPlay.selection(folder: "../World", instanceID: id, paths: paths) }
        let world = try WorldQuickPlay.selection(folder: "World", instanceID: id, paths: paths)
        try FileManager.default.removeItem(at: worldURL)
        var current = GameInstance(name: "Current", gameVersion: "1.21.1"); current.id = id
        #expect(throws: (any Error).self) { try WorldQuickPlay.validate(world, instance: current, manifest: manifest, paths: paths) }
    }
}
