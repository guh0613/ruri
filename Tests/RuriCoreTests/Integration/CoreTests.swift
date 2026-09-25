import Testing
import Foundation
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
        #expect(arg.values(architecture: "aarch64", features: ["has_custom_resolution": true]) == ["--width", "${resolution_width}"])
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
        #expect(throws: (any Error).self) { try Account(username: "bad name") }
    }
    @Test func mavenCoordinates() throws {
        #expect(try Library.mavenPath("org.lwjgl:lwjgl:3.3.3:natives-macos-arm64") == "org/lwjgl/lwjgl/3.3.3/lwjgl-3.3.3-natives-macos-arm64.jar")
        #expect(try Library.mavenPath("net.test:thing:1.0@zip") == "net/test/thing/1.0/thing-1.0.zip")
        #expect(throws: (any Error).self) { try Library.mavenPath("../../escape:foo:1") }
    }
}
