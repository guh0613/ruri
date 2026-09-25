import Foundation
import Testing
@testable import RuriCore

struct PackLaunchSettingsTests {
    @Test func argumentArraysRoundTripWithoutShellInterpretation() throws {
        let values = ["", "two words", "it's fine", "a\"b", "C:\\path\\file", "$(touch /tmp/example)", "中文\n换行"]
        #expect(try ArgumentTokenizer.split(ArgumentTokenizer.join(values)) == values)
    }
    @Test func additionalGameArgumentsPreserveIdentityAndJavaRequirements() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1.0","mainClass":"Game","libraries":[],"javaVersion":{"majorVersion":8},"arguments":{"game":["--username","${auth_player_name}"]}}"#.utf8))
        var instance = GameInstance(name: "Pack", gameVersion: "1.0"); instance.supportedJavaMajors = [8]
        let jar = paths.versions.appendingPathComponent("1.0/1.0.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("stub".utf8).write(to: jar)
        let java = JavaRuntime(path: "/test/java", version: "8", major: 8, architecture: "x86_64", vendor: "Fixture")
        let account = try Account(username: "Player")
        instance.extraGameArguments = "--server play.example.test --port 25565"
        let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths)
        #expect(plan.arguments.contains("play.example.test")); #expect(plan.arguments.contains("25565"))
        for argument in ["--gameDir=/tmp/other", "--username AnotherPlayer", "--accessToken=secret"] {
            instance.extraGameArguments = argument
            #expect(throws: (any Error).self) { try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths) }
        }
        instance.extraGameArguments = nil; instance.supportedJavaMajors = [17]
        #expect(throws: (any Error).self) { try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths) }
    }
    @Test func packLibrariesReplaceCoordinatesAndRejectUnsafeURLs() throws {
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"1","libraries":[{"name":"test:library:1"},{"name":"test:keep:1"}]}"#.utf8))
        let extra = try JSONDecoder().decode([Library].self, from: Data(#"[{"name":"test:library:2","url":"https://example.test/maven/"},{"name":"test:extra:1"}]"#.utf8))
        let merged = try GameInstaller.applyingPackLibraries(extra, to: manifest)
        #expect(merged.libraries.map(\.name) == ["test:keep:1", "test:library:2", "test:extra:1"])
        let invalid = try JSONDecoder().decode([Library].self, from: Data(#"[{"name":"test:library:2","url":"file:///tmp/private/"}]"#.utf8))
        #expect(throws: (any Error).self) { try GameInstaller.applyingPackLibraries(invalid, to: manifest) }
    }
}
