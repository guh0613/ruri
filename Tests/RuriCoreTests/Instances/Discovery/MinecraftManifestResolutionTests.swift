import Foundation
import Testing
@testable import RuriCore

struct MinecraftManifestResolutionTests {
    typealias Fixture = MinecraftDirectoryReaderTests.Fixture
    private func resolve(_ fixture: Fixture, _ id: String) async throws -> MinecraftManifestResolution {
        let reader = MinecraftDirectoryReader(), catalog = try await reader.scan(fixture.root)
        return try await reader.resolveManifest(#require(catalog.versions.first { $0.id == id }), in: catalog)
    }
    private func strings(_ arguments: [LaunchArgument]?) -> [String] {
        (arguments ?? []).flatMap { $0.values(architecture: "aarch64", features: [:]) }
    }

    @Test func hmclRootRebuildsFromStablePriorityOrderWithoutApplyingCachedFieldsTwice() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let patches: [[String: Any]] = [
            ["id": "forge", "version": "52.1.16", "priority": 30_000, "mainClass": "fixture.Forge", "arguments": ["jvm": ["-Dpatch=first"], "game": ["--fml.mcVersion", "1.21.1"]], "libraries": [["name": "fixture:loader:2"]]],
            ["id": "game", "version": "1.21.1", "priority": 0, "mainClass": "net.minecraft.client.main.Main", "arguments": ["jvm": ["-cp", "${classpath}"], "game": ["--username", "${auth_player_name}"]], "libraries": [["name": "fixture:base:1"]]],
            ["id": "early", "arguments": ["jvm": ["-Dearly=true"]]],
            ["id": "custom", "priority": 30_000, "mainClass": "fixture.Final", "arguments": ["jvm": ["-Dpatch=second"]], "libraries": [["name": "fixture:custom:1"]]]
        ]
        try f.version("Renamed", values: ["root": true, "mainClass": "stale.Cached", "jar": "Original client", "arguments": ["jvm": ["-Dduplicate=must-not-survive"]], "libraries": [["name": "fixture:stale:9"]], "patches": patches])
        let result = try await resolve(f, "Renamed")
        #expect(result.manifest.id == "Renamed" && result.manifest.mainClass == "fixture.Final")
        #expect(result.clientFile == f.root.appendingPathComponent("versions/Original client/Original client.jar"))
        #expect(strings(result.manifest.arguments?.jvm) == ["-Dearly=true", "-cp", "${classpath}", "-Dpatch=first", "-Dpatch=second"])
        #expect(strings(result.manifest.arguments?.game) == ["--username", "${auth_player_name}", "--fml.mcVersion", "1.21.1"])
        #expect(result.manifest.libraries.map(\.name) == ["fixture:base:1", "fixture:loader:2", "fixture:custom:1"])
        var reader = MinecraftDirectoryScan(root: f.root)
        let graph = try reader.manifestGraph("Renamed")
        #expect(graph.value["patches"] == nil && graph.value["inheritsFrom"] == nil)
        #expect(try reader.version("Renamed").gameVersion == "1.21.1")
    }

    @Test func caseInsensitiveDownloadTypesResolveToTheClientUsedByRuri() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.version("1.21.1", values: ["mainClass": "fixture.Main", "downloads": ["CLIENT": ["url": "https://fixture.invalid/client.jar"]], "logging": ["CLIENT": ["argument": "-Dconfiguration=${path}", "file": ["id": "client.xml", "url": "https://fixture.invalid/client.xml"]]]])
        let result = try await resolve(f, "1.21.1")
        #expect(result.manifest.downloads?["client"]?.url?.lastPathComponent == "client.jar")
        #expect(result.manifest.logging?.client?.file.id == "client.xml")
        let source = try #require(result.sourceManifests.first?.data)
        #expect(String(decoding: source, as: UTF8.self).contains("CLIENT"))
    }

    @Test func inheritedFieldsAndExplicitEmptyMapsFollowTheirDifferentMergeRules() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let mac: [[String: Any]] = [["action": "allow", "os": ["name": "osx"]]]
        let windows: [[String: Any]] = [["action": "allow", "os": ["name": "windows"]]]
        try f.version("1.21.1", values: ["mainClass": "fixture.Parent", "minecraftArguments": "--old base", "arguments": ["jvm": ["-Dparent=true"], "game": ["--base"]], "assets": "legacy", "javaVersion": ["majorVersion": 17], "compatibilityRules": mac, "downloads": ["client": ["url": "https://fixture.invalid/client.jar"]], "libraries": [["name": "fixture:variant:1", "rules": windows]]])
        try f.version("Child", values: ["inheritsFrom": "1.21.1", "minecraftArguments": "--child replacement", "arguments": ["game": ["--child"]], "downloads": [:], "libraries": [["name": "fixture:variant:2", "rules": mac]], "patches": [["id": "last", "priority": 1, "minecraftArguments": "--patch final", "javaVersion": ["majorVersion": 21], "arguments": ["jvm": ["-Dpatch=true"]], "libraries": [["name": "fixture:extra:3"]]]]])
        let result = try await resolve(f, "Child"), manifest = result.manifest
        #expect(manifest.inheritsFrom == nil && manifest.mainClass == "fixture.Parent" && manifest.jar == "1.21.1")
        #expect(manifest.assets == "legacy" && manifest.javaVersion?.majorVersion == 21)
        #expect(manifest.downloads?.isEmpty == true && manifest.minecraftArguments == "--patch final")
        #expect(strings(manifest.arguments?.game) == ["--base", "--child"])
        #expect(strings(manifest.arguments?.jvm) == ["-Dparent=true", "-Dpatch=true"])
        #expect(manifest.libraries.map(\.name) == ["fixture:variant:2", "fixture:variant:1", "fixture:extra:3"])
        #expect(manifest.libraries[0].rules?.first?.os?.name == "osx")
        #expect(manifest.libraries[1].rules?.first?.os?.name == "windows")
        #expect(manifest.compatibilityRules?.first?.os?.name == "osx")
    }

    @Test func aNonRootManifestKeepsItsOwnFieldsAndRenamedFoldersDefineClientIdentity() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        for flag in [false, true] {
            try f.version("Renamed base", values: ["id": "stale original name", "root": flag, "jar": NSNull(), "mainClass": "fixture.Base", "libraries": []])
            try f.version("Child", values: ["inheritsFrom": "Renamed base", "jar": NSNull(), "root": true, "patches": [["id": "extension", "jar": "must-not-replace-client", "arguments": ["game": ["--extension"]]]]])
            let result = try await resolve(f, "Child")
            #expect(result.manifest.mainClass == "fixture.Base" && result.manifest.jar == "Renamed base")
            #expect(result.clientFile == f.root.appendingPathComponent("versions/Renamed base/Renamed base.jar"))
        }
        try f.version("Nonroot patches", values: ["mainClass": "fixture.Base", "arguments": ["jvm": ["-Dbase=true"]], "patches": [["id": "extension", "arguments": ["jvm": ["-Dextra=true"]]]]])
        #expect(strings(try await resolve(f, "Nonroot patches").manifest.arguments?.jvm) == ["-Dbase=true", "-Dextra=true"])
        try f.version("Empty root", values: ["root": true, "mainClass": "must.not.be.used", "patches": []])
        await #expect(throws: (any Error).self) { try await resolve(f, "Empty root") }
    }

    @Test func localHintsKeepExactFilenamesAndResolveRelativeToTheSelectedVersion() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.version("1.21.1", values: ["mainClass": "fixture.Main", "libraries": [["name": "fixture:local-parent:1", "hint": "local", "filename": "parent library.jar"]]])
        try f.version("Selected", values: ["inheritsFrom": "1.21.1", "libraries": [
            ["name": "fixture:renamed:1", "MMC-hint": "local", "MMC-filename": "local/custom payload.jar"],
            ["name": "fixture:default:2:classifier@zip", "hint": "local"],
            ["name": "fixture:remote:1", "url": "https://fixture.invalid/maven/"]
        ], "customUnrecognizedField": ["preserve": "original manifest"]])
        try f.json(["profiles": ["private": ["lastVersionId": "Selected"]], "secret": "must-not-be-persisted"], "launcher_profiles.json")
        let before = try FileTreeManifest.capture(in: f.root)
        let result = try await resolve(f, "Selected")
        let folder = f.root.appendingPathComponent("versions/Selected/libraries")
        #expect(result.libraries.map(\.localFile) == [folder.appendingPathComponent("local/custom payload.jar"), folder.appendingPathComponent("default-2-classifier.zip"), nil, folder.appendingPathComponent("parent library.jar")])
        #expect(result.sourceManifests.count == 2)
        #expect(result.sourceManifests.allSatisfy { $0.url.path.contains("/versions/") })
        let preserved = try #require(result.sourceManifests.first { $0.url.lastPathComponent == "Selected.json" }?.data)
        #expect(String(decoding: preserved, as: UTF8.self).contains("customUnrecognizedField"))
        #expect(!result.sourceManifests.contains { String(decoding: $0.data ?? Data(), as: UTF8.self).contains("must-not-be-persisted") })
        try before.requireMatch(in: f.root)
    }

    @Test func rejectsInvalidPriorityWithoutHidingOtherVersions() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.version("1.21.1", values: ["mainClass": "fixture.Main"])
        let invalid: [[String: Any]] = [
            ["patches": [["id": "boolean", "priority": true]]],
            ["patches": [["id": "fraction", "priority": 1.5]]],
            ["patches": [["id": "large", "priority": Int64(Int32.max) + 1]]],
            ["root": 1]
        ]
        for (index, value) in invalid.enumerated() { try f.version("Bad \(index)", values: value) }
        let catalog = try await MinecraftDirectoryReader().scan(f.root)
        #expect(catalog.versions.filter { $0.issue == nil }.map(\.id) == ["1.21.1"])
    }

    @Test func patchOriginMetadataDoesNotBecomeExecutableInheritance() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.version("1.21.1", values: ["root": true, "patches": [["id": "game", "mainClass": "fixture.TopLevel", "inheritsFrom": "Unavailable old parent", "patches": [["id": "nested", "mainClass": "must.not.execute"]]]]])
        let result = try await resolve(f, "1.21.1")
        #expect(result.manifest.mainClass == "fixture.TopLevel")
        #expect(result.warnings.count == 1 && result.warnings[0].contains("仅合并顶层"))
        #expect(result.sourceManifests.count == 1)
    }

    @Test func localFilenameTraversalAndStaleParentSnapshotsAreRejected() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.version("1.21.1", values: ["mainClass": "fixture.Main"])
        for filename in ["../outside.jar", "/absolute.jar", "bad\\path.jar", ""] {
            try f.version("Child", values: ["inheritsFrom": "1.21.1", "libraries": [["name": "fixture:local:1", "hint": "local", "filename": filename]]])
            await #expect(throws: (any Error).self) { try await resolve(f, "Child") }
        }
        try f.version("Child", values: ["inheritsFrom": "1.21.1"])
        let reader = MinecraftDirectoryReader(), catalog = try await reader.scan(f.root)
        let child = try #require(catalog.versions.first { $0.id == "Child" })
        try f.version("1.21.1", values: ["mainClass": "fixture.Changed"])
        await #expect(throws: (any Error).self) { try await reader.resolveManifest(child, in: catalog) }
        let fresh = try await reader.scan(f.root), selected = try #require(fresh.versions.first { $0.id == "Child" })
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await reader.resolveManifest(selected, in: fresh) }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    }

    @Test func incompatibleTopLevelRulesPreventLaunchAndRepairBeforeFileWork() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"fixture","mainClass":"fixture.Main","libraries":[],"compatibilityRules":[{"action":"allow","os":{"name":"windows"}}]}"#.utf8))
        let paths = LauncherPaths(root: f.root.appendingPathComponent("Ruri")), game = GameInstance(name: "Incompatible", gameVersion: "1.21.1")
        try paths.prepareInstance(game.id)
        try JSONEncoder().encode(manifest).write(to: paths.manifest(game.id))
        let java = JavaRuntime(path: "/fixture/java", version: "21", major: 21, architecture: GameInstaller.architecture(for: manifest), vendor: "Fixture")
        do { _ = try LaunchBuilder.build(instance: game, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths); Issue.record("Expected compatibility rejection") }
        catch { #expect(error.localizedDescription.contains("兼容规则")) }
        do { try await GameInstaller(paths: paths).repair(game) { _ in }; Issue.record("Expected compatibility rejection") }
        catch { #expect(error.localizedDescription.contains("兼容规则")) }
        #expect(!FileManager.default.fileExists(atPath: paths.game(game.id).path))
    }
}
