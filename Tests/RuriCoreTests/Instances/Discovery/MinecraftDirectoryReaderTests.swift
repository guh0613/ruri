import Foundation
import Testing
@testable import RuriCore

struct MinecraftDirectoryReaderTests {
    struct Fixture {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-existing-minecraft-\(UUID())").resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: root.appendingPathComponent("versions"), withIntermediateDirectories: true)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
        func json(_ value: [String: Any], _ path: String) throws {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: file)
        }
        func version(_ id: String, values: [String: Any] = [:]) throws {
            var manifest: [String: Any] = ["id": id, "libraries": []]
            manifest.merge(values) { _, new in new }; try json(manifest, "versions/\(id)/\(id).json")
        }
    }

    @Test func scansInheritedAndRenamedVersionsWithoutWritingSourceData() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("Renamed base")
        try fixture.version("Fabric world", values: ["inheritsFrom": "Renamed base", "libraries": [["name": "net.fabricmc:fabric-loader:0.19.5"]]])
        let empty = fixture.root.appendingPathComponent("jar-input")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        try SafeArchive.create(from: empty, to: fixture.root.appendingPathComponent("versions/Renamed base/Renamed base.jar"), additionalFiles: ["version.json": Data(#"{"id":"1.21.1"}"#.utf8)])
        let before = try FileTreeManifest.capture(in: fixture.root)
        let reader = MinecraftDirectoryReader()
        let catalog = try await reader.scan(fixture.root.appendingPathComponent("versions/Fabric world/Fabric world.json"))
        #expect(catalog.selectedVersionID == "Fabric world" && catalog.versions.count == 2)
        let version = try #require(catalog.versions.first { $0.id == "Fabric world" })
        #expect(version.gameVersion == "1.21.1" && version.components == [.init(name: "Fabric", version: "0.19.5")])
        #expect(version.suggestedLocationID == nil && version.gameLocations.count == 2 && version.issue == nil)
        try await reader.validate(version, in: catalog)
        try before.requireMatch(in: fixture.root)
    }

    @Test func brokenVersionsAndCyclesDoNotHideReadableVersions() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("1.21.1")
        try fixture.version("Cycle A", values: ["inheritsFrom": "Cycle B"])
        try fixture.version("Cycle B", values: ["inheritsFrom": "Cycle A"])
        try fixture.version("Missing parent", values: ["inheritsFrom": "Absent"])
        try fixture.version("Traversal", values: ["inheritsFrom": "../outside"])
        let catalog = try await MinecraftDirectoryReader().scan(fixture.root)
        #expect(catalog.versions.count == 5)
        #expect(catalog.versions.filter { $0.issue == nil }.map(\.id) == ["1.21.1"])
    }

    @Test func modernHMCLSettingsDistinguishExplicitIsolationFromInheritedPresets() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("1.21.1"); try fixture.version("1.20.1")
        try fixture.json(["overrideProperties": ["runningDirectory"], "runningDirectory": ""], "versions/1.21.1/.hmcl/config/instance-game-settings.json")
        try fixture.json(["overrideProperties": [], "runningDirectory": "/ignored"], "versions/1.20.1/.hmcl/config/instance-game-settings.json")
        let catalog = try await MinecraftDirectoryReader().scan(fixture.root)
        #expect(catalog.versions.first { $0.id == "1.21.1" }?.suggestedLocationID == fixture.root.appendingPathComponent("versions/1.21.1").path)
        #expect(catalog.versions.first { $0.id == "1.20.1" }?.suggestedLocationID == nil)
    }

    @Test func legacyCustomDirectoriesAndModpacksKeepTheirActualLocation() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("1.21.1"); try fixture.version("Pack", values: ["jar": "1.21.1"])
        let custom = fixture.root.appendingPathComponent("Worlds elsewhere")
        try FileManager.default.createDirectory(at: custom.appendingPathComponent("saves"), withIntermediateDirectories: true)
        try fixture.json(["usesGlobal": false, "gameDirType": 2, "gameDir": custom.path], "versions/1.21.1/hmclversion.cfg")
        try fixture.json([:], "versions/Pack/modpack.cfg")
        try fixture.json(["usesGlobal": false, "gameDirType": "ROOT_FOLDER"], "versions/Pack/hmclversion.cfg")
        let catalog = try await MinecraftDirectoryReader().scan(fixture.root)
        let version = try #require(catalog.versions.first { $0.id == "1.21.1" })
        #expect(version.suggestedLocationID == custom.path)
        #expect(catalog.versions.first { $0.id == "Pack" }?.suggestedLocationID == fixture.root.appendingPathComponent("versions/Pack").path)
    }

    @Test func officialProfilesCanExposeSeveralGameDirectoriesForTheSameVersion() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("1.21.1"); try fixture.version("1.20.1")
        try fixture.json(["profiles": ["a": ["lastVersionId": "1.21.1"], "b": ["lastVersionId": "1.21.1", "gameDir": fixture.root.appendingPathComponent("custom").path], "c": ["lastVersionId": "1.20.1"]]], "launcher_profiles.json")
        let catalog = try await MinecraftDirectoryReader().scan(fixture.root)
        let ambiguous = try #require(catalog.versions.first { $0.id == "1.21.1" })
        #expect(ambiguous.gameLocations.count == 3 && ambiguous.suggestedLocationID == nil)
        #expect(catalog.versions.first { $0.id == "1.20.1" }?.suggestedLocationID == fixture.root.path)
    }

    @Test func detectsPatchedComponentsWithoutCallingEveryUnknownVersionVanilla() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("Adventure", values: ["patches": [["id": "game", "version": "1.21.1"], ["id": "forge", "version": "52.1.16"], ["id": "optifine", "version": "HD_U_J4"]]])
        try fixture.version("1.21.1-unknown-loader")
        try fixture.version("Neo", values: ["arguments": ["game": ["--fml.mcVersion", "1.21.1", "--fml.neoForgeVersion", "21.1.250"]], "libraries": [["name": "net.neoforged:neoforge:21.1.250"]]])
        let catalog = try await MinecraftDirectoryReader().scan(fixture.root)
        let patched = try #require(catalog.versions.first { $0.id == "Adventure" })
        #expect(patched.gameVersion == "1.21.1" && patched.components.map(\.name) == ["Forge", "OptiFine"])
        #expect(catalog.versions.first { $0.id == "1.21.1-unknown-loader" }?.gameVersion == nil)
        #expect(catalog.versions.first { $0.id == "Neo" }?.components == [.init(name: "NeoForge", version: "21.1.250")])
    }

    @Test func detectsSettingsThatWereAddedOrChangedAfterThePreview() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("1.21.1")
        let reader = MinecraftDirectoryReader(), first = try await reader.scan(fixture.root)
        try fixture.json(["usesGlobal": false, "gameDirType": "VERSION_FOLDER"], "versions/1.21.1/hmclversion.cfg")
        await #expect(throws: (any Error).self) { try await reader.validate(first.versions[0], in: first) }
        let second = try await reader.scan(fixture.root)
        try fixture.version("1.21.1", values: ["libraries": [["name": "net.fabricmc:fabric-loader:0.19.5"]]])
        await #expect(throws: (any Error).self) { try await reader.validate(second.versions[0], in: second) }
    }

    @Test func rejectsLinksAndUnrelatedFilesAndSupportsCancellation() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        try fixture.version("1.21.1")
        let link = fixture.root.appendingPathComponent("versions/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.root.appendingPathComponent("versions/1.21.1"))
        let reader = MinecraftDirectoryReader()
        let catalog = try await reader.scan(fixture.root.appendingPathComponent("versions"))
        #expect(catalog.versions.first { $0.id == "link" }?.issue != nil)
        try fixture.json([:], "options.json")
        await #expect(throws: (any Error).self) { try await reader.scan(fixture.root.appendingPathComponent("options.json")) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await reader.scan(fixture.root)
        }
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
    }
}
