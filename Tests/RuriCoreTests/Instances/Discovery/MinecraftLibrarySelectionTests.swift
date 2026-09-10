import Foundation
import Testing
@testable import RuriCore

struct MinecraftLibrarySelectionTests {
    private func declaration(_ name: String, fields: [String: Any] = [:], local: String? = nil) throws -> MinecraftLibraryDeclaration {
        var raw = fields; raw["name"] = name
        let data = try JSONSerialization.data(withJSONObject: raw)
        return .init(library: try JSONDecoder().decode(Library.self, from: data), localFile: local.map { URL(fileURLWithPath: $0) }, sourceMetadata: data)
    }

    @Test func dependencyOrderingHandlesNumericSegmentsPrereleasesAndLargeNumbers() {
        let ordered = [
            ("1.9", "1.10"), ("1.8.0_51", "1.8.0.51"), ("1.8.0_77", "1.8.0_151"),
            ("1.12.2-14.23.4.2739", "1.12.2-14.23.5.2760"),
            ("1.99999999999999999999", "1.199999999999999999999"),
            ("1.99999999999999999999", "2"), ("1.0-beta.1", "1.0"),
            ("1.0-alpha.1", "1.0-beta.1"), ("1.0", "1.0-snapshot"),
            ("3.6.15", "3.6.15.289"), ("1.0rc2", "1.0rc10"), ("1-e\u{301}", "1-é")
        ]
        for (first, second) in ordered {
            #expect(MinecraftDependencyVersion.compare(first, second) == .orderedAscending)
            #expect(MinecraftDependencyVersion.compare(second, first) == .orderedDescending)
        }
        for (first, second) in [("3.2.0.0", "3.2"), ("3.2.0.0-0", "3.2"), ("3.2--------", "3.2"), ("3.0002", "3.2"), ("1.0099999999999999999999", "1.99999999999999999999")] {
            #expect(MinecraftDependencyVersion.compare(first, second) == .orderedSame)
        }
    }

    @Test func newerVersionsReplaceEveryOlderVariantAndExplanationsNameTheFinalSelection() throws {
        let native: [String: Any] = ["natives": ["osx": "natives-osx"], "downloads": ["classifiers": ["natives-osx": ["path": "native.jar"]]]]
        let input = try [declaration("fixture:library:1"), declaration("fixture:library:1", fields: native),
                         declaration("fixture:unrelated:1"), declaration("fixture:library:2"), declaration("fixture:library:3"),
                         declaration("fixture:library:3", fields: native), declaration("fixture:library:2", fields: native)]
        let result = try MinecraftLibrarySelector.select(input)
        #expect(result.libraries.map(\.library.name) == ["fixture:library:3", "fixture:unrelated:1", "fixture:library:3"])
        #expect(result.libraries.last?.library.natives != nil)
        #expect(result.discarded.count == 4)
        #expect(result.discarded.allSatisfy { $0.selectedName == "fixture:library:3" && $0.reason == .olderVersion })
    }

    @Test func differentRulesAndClassifiersRemainDistinct() throws {
        let mac: [String: Any] = ["rules": [["action": "allow", "os": ["name": "osx"]]]]
        let windows: [String: Any] = ["rules": [["action": "allow", "os": ["name": "windows"]]]]
        let input = try [declaration("fixture:library:1", fields: mac), declaration("fixture:library:5", fields: windows),
                         declaration("fixture:library:6:natives-macos", fields: mac), declaration("fixture:library:6:natives-macos-arm64", fields: mac)]
        let selected = try MinecraftLibrarySelector.select(input)
        #expect(selected.libraries.map(\.library.name) == ["fixture:library:6:natives-macos", "fixture:library:5", "fixture:library:6:natives-macos-arm64"])
        #expect(selected.discarded.count == 1 && selected.discarded.first?.name == "fixture:library:1")
    }

    @Test func metadataSelectionKeepsTheMatchingLocalFilenameAndIgnoresUnrecognizedPadding() throws {
        let remote = try declaration("fixture:library:1", fields: ["unrecognized": String(repeating: "padding", count: 1000)])
        let local = try declaration("fixture:library:1", fields: ["hint": "local", "filename": "custom file.jar"], local: "/fixture/custom file.jar")
        let result = try MinecraftLibrarySelector.select([remote, local])
        #expect(result.libraries.count == 1 && result.libraries[0].localFile == local.localFile)
        let richer = try declaration("fixture:library:1", fields: ["hint": "local", "filename": "second custom file.jar", "downloads": ["artifact": ["path": "private.jar", "sha1": String(repeating: "a", count: 40)]]], local: "/fixture/second custom file.jar")
        let changed = try MinecraftLibrarySelector.select([local, richer])
        #expect(changed.libraries[0].localFile == richer.localFile)
        #expect(try changed.libraries[0].library.artifact()?.path == "private.jar")
        #expect(changed.discarded.count == 1 && changed.discarded[0].reason == .duplicateDeclaration)
    }

    @Test func equalMetadataKeepsOriginalPrecedenceAndCoordinateEquivalentVersionsKeepTheirFiles() throws {
        let a = try declaration("fixture:library:1", fields: ["url": "https://a.invalid/"])
        let b = try declaration("fixture:library:1", fields: ["url": "https://b.invalid/"])
        #expect(try MinecraftLibrarySelector.select([a, b]).libraries[0].library.url == a.library.url)
        #expect(try MinecraftLibrarySelector.select([b, a]).libraries[0].library.url == b.library.url)
        let equivalent = try declaration("fixture:library:1.0")
        #expect(try MinecraftLibrarySelector.select([a, equivalent]).libraries.count == 2)
    }

    @Test func importNormalizesEmptyRulesAndKeepsConditionalArguments() throws {
        let empty = try declaration("fixture:library:1", fields: ["rules": []])
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"fixture","libraries":[],"arguments":{"jvm":[{"rules":[],"value":["-Dunconditional=true"]},{"rules":[{"action":"allow","os":{"name":"windows"}}],"value":"-Dwindows=true"}]}}"#.utf8))
        let resolution = MinecraftManifestResolution(manifest: manifest, clientFile: URL(fileURLWithPath: "/fixture/client.jar"), libraries: [empty], warnings: [], sourceManifests: [])
        let result = try resolution.selectingLibraries()
        #expect(result.manifest.libraries[0].rules == nil)
        #expect(GameInstaller.allowed(result.manifest.libraries[0], architecture: "aarch64"))
        #expect(result.manifest.arguments?.jvm?.flatMap { $0.values(architecture: "aarch64", features: [:]) } == ["-Dunconditional=true"])
        #expect(result.libraries[0].sourceMetadata == empty.sourceMetadata)
        #expect(!Rule.allows([], architecture: "aarch64"))
    }

    @Test func rejectsMalformedCoordinatesUnboundedVersionDepthAndCancellation() throws {
        for name in ["missing:version", "fixture:library:1@jar@zip", "fixture:library:" + String(repeating: "1-", count: 200)] {
            let library = try declaration(name)
            #expect(throws: (any Error).self) { try MinecraftLibrarySelector.select([library]) }
        }
    }

    @Test func cancellationStopsLibrarySelection() async throws {
        let library = try declaration("fixture:library:1")
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try MinecraftLibrarySelector.select([library]).libraries.count }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func directoryDiscoveryUsesSelectedDependenciesAndPrefersTheMacVariant() async throws {
        let f = try MinecraftDirectoryReaderTests.Fixture(); defer { f.cleanup() }
        try f.version("1.21.1", values: ["mainClass": "fixture.Main", "libraries": [["name": "net.fabricmc:fabric-loader:0.19.5"]]])
        try f.version("Older child", values: ["inheritsFrom": "1.21.1", "libraries": [["name": "net.fabricmc:fabric-loader:0.16.10"]]])
        try f.version("Platforms", values: ["jar": "1.21.1", "mainClass": "fixture.Main", "libraries": [
            ["name": "net.fabricmc:fabric-loader:0.19.5", "rules": [["action": "allow", "os": ["name": "osx"]]]],
            ["name": "net.fabricmc:fabric-loader:99.0", "rules": [["action": "allow", "os": ["name": "windows"]]]]
        ]])
        let reader = MinecraftDirectoryReader(), catalog = try await reader.scan(f.root)
        for id in ["Older child", "Platforms"] {
            let version = try #require(catalog.versions.first { $0.id == id })
            #expect(version.components == [.init(name: "Fabric", version: "0.19.5")])
        }
        let child = try #require(catalog.versions.first { $0.id == "Older child" })
        let resolved = try await reader.resolveManifest(child, in: catalog)
        #expect(try resolved.selectingLibraries().manifest.libraries.map(\.name) == ["net.fabricmc:fabric-loader:0.19.5"])
    }
}
