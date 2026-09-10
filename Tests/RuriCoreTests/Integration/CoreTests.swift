import Testing
import Foundation
import CryptoKit
@testable import RuriCore

struct CoreTests {
    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    @Test func orderedRules() throws {
        let rules = try decode([Rule].self, #"[{"action":"allow"},{"action":"disallow","os":{"name":"windows"}},{"action":"disallow","features":{"is_demo_user":true}}]"#)
        #expect(Rule.allows(rules, architecture: "aarch64"))
        #expect(!Rule.allows(rules, architecture: "aarch64", features: ["is_demo_user": true]))
        #expect(!Rule.allows([], architecture: "aarch64"))
        #expect(Rule.allows(nil, architecture: "aarch64"))
    }
    @Test func conditionalArguments() throws {
        let arg = try decode(LaunchArgument.self, #"{"rules":[{"action":"allow","features":{"has_custom_resolution":true}}],"value":["--width","${resolution_width}"]}"#)
        #expect(arg.values(architecture: "aarch64", features: [:]).isEmpty)
        #expect(arg.values(architecture: "aarch64", features: ["has_custom_resolution": true]).count == 2)
    }
    @Test func argumentQuoting() throws {
        #expect(try ArgumentTokenizer.split(#"-Dfoo="a b" '-Dbar=c d' -Xmx4G"#) == ["-Dfoo=a b", "-Dbar=c d", "-Xmx4G"])
        #expect(throws: (any Error).self) { try ArgumentTokenizer.split("\"unterminated") }
        #expect(try ArgumentTokenizer.split("$(touch /tmp/nope)") == ["$(touch", "/tmp/nope)"])
    }
    @Test func pathContainment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for invalid in ["../escape", "/tmp/escape", "a/../../escape", "a\\b"] {
            #expect(throws: (any Error).self) { try LauncherPaths.safePath(invalid, within: root) }
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.deletingLastPathComponent())
        #expect(throws: (any Error).self) { try LauncherPaths.safePath("link/escape", within: root) }
        #expect(try LauncherPaths.safePath("mods/foo.jar", within: root).path.hasSuffix("mods/foo.jar"))
    }
    @Test func offlineUUID() throws {
        #expect(try Account(username: "Notch").uuid == "b50ad385829d3141a2167e7d7539ba7f")
        #expect(try Account(username: "Notch").uuid == Account(username: "Notch").uuid)
        #expect(throws: (any Error).self) { try Account(username: "bad name") }
    }
    @Test func mavenCoordinates() throws {
        #expect(try Library.mavenPath("org.lwjgl:lwjgl:3.3.3:natives-macos-arm64") == "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos-arm64.jar")
        #expect(try Library.mavenPath("net.test:thing:1.0@zip") == "net/test/thing/1.0/thing-1.0.zip")
        #expect(throws: (any Error).self) { try Library.mavenPath("../../escape:foo:1") }
    }
    @Test func manifestInheritanceReplacesLibraries() throws {
        let base = try decode(VersionManifest.self, #"{"id":"1.21.1","mainClass":"vanilla.Main","libraries":[{"name":"org.test:lib:1"},{"name":"org.keep:lib:2"}],"arguments":{"game":["--username","${auth_player_name}"]},"javaVersion":{"majorVersion":21}}"#)
        let child = try decode(VersionManifest.self, #"{"id":"fabric-1.21.1","inheritsFrom":"1.21.1","mainClass":"fabric.Main","libraries":[{"name":"org.test:lib:2"}],"arguments":{"game":["--fabric"]}}"#)
        let merged = base.merging(child: child)
        #expect(merged.mainClass == "fabric.Main")
        #expect(merged.jar == "1.21.1")
        #expect(merged.inheritsFrom == nil)
        #expect(merged.requiredJava == 21)
        #expect(merged.libraries.map(\.name) == ["org.keep:lib:2", "org.test:lib:2"])
        #expect(merged.arguments?.game?.count == 3)
    }
    @Test func architectureFiltering() throws {
        let arm = try decode(Library.self, #"{"name":"org.lwjgl:lwjgl:3.3.3:natives-macos-arm64","rules":[{"action":"allow","os":{"name":"osx"}}]}"#)
        let intel = try decode(Library.self, #"{"name":"org.lwjgl:lwjgl:3.3.3:natives-macos","rules":[{"action":"allow","os":{"name":"osx"}}]}"#)
        #expect(GameInstaller.allowed(arm, architecture: "aarch64"))
        #expect(!GameInstaller.allowed(intel, architecture: "aarch64"))
        #expect(GameInstaller.allowed(intel, architecture: "x86_64"))
        #expect(!GameInstaller.allowed(arm, architecture: "x86_64"))
    }
    @Test func javaSelectionRequiresCompatibleMajor() throws {
        let runtimes = [JavaRuntime(path: "/a", version: "25", major: 25, architecture: "aarch64", vendor: "Test"), JavaRuntime(path: "/b", version: "21", major: 21, architecture: "aarch64", vendor: "Test")]
        #expect(try JavaDiscovery.select(from: runtimes, major: 21).path == "/b")
        #expect(throws: (any Error).self) { try JavaDiscovery.select(from: runtimes, major: 8) }
        #expect(throws: (any Error).self) { try JavaDiscovery.select(from: runtimes, major: 21, architecture: "x86_64") }
    }
    @Test func downloadsValidateHashAndSize() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("hello".utf8).write(to: file)
        let item = DownloadItem(url: URL(string: "https://example.com/a")!, destination: file, sha1: "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d", size: 5)
        #expect(DownloadManager.valid(file, item: item))
        try Data("wrong".utf8).write(to: file)
        #expect(!DownloadManager.valid(file, item: item))
    }
    @Test func persistenceRoundTrip() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var state = PersistentState()
        state.instances = [GameInstance(name: "中文实例", gameVersion: "1.21.1")]
        state.accounts = [try Account(username: "Player")]
        try StateStore.save(state, to: paths)
        let result = try StateStore.load(paths)
        #expect(result.instances == state.instances)
        #expect(result.accounts == state.accounts)
    }
}
