import Foundation
import Testing
@testable import RuriCore

struct LoaderSelectionTests {
    @Test func combinedPortableAndMCBBSPacksRoundTripEveryLoader() async throws {
        let (paths, original) = try InstanceTransferTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = original; instance.gameVersion = "1.12.2"
        instance.setLoaderSelections([.init(loader: .forge, version: "14.23.5.2860"), .init(loader: .optifine, version: "HD_U_G5")])
        let transfer = InstanceTransfer(paths: paths)
        for format in [InstanceExportFormat.ruri, .mcbbs] {
            let url = paths.cache.appendingPathComponent("combined-" + format.rawValue + ".zip")
            try await transfer.export(instance, to: url, format: format)
            let prepared = try await transfer.prepare(url)
            #expect(prepared.instance.loaderSelections == instance.loaderSelections)
            await transfer.discard(prepared)
        }
        await #expect(throws: (any Error).self) {
            try await transfer.export(instance, to: paths.cache.appendingPathComponent("unsupported.mrpack"), format: .mrpack)
        }
    }

    @Test func versionCatalogChecksGameMappingsAndKeepsReleaseChannels() async throws {
        let fixture = EndpointHTTPFixture([
            "meta.fabricmc.net/v2/versions/game": Data(#"[{"version":"1.21.1"}]"#.utf8),
            "meta.fabricmc.net/v2/versions/loader/1.21.1": Data(#"[{"loader":{"version":"0.16.9","stable":true},"intermediary":{"version":"1.21.1"}},{"loader":{"version":"0.17.0-beta.2","stable":false},"intermediary":{"version":"1.21.1"}},{"loader":{"version":"0.16.10","stable":true},"intermediary":{"version":"1.21.1"}},{"loader":{"version":"0.99.0","stable":true},"intermediary":{"version":"1.20.1"}},{"loader":{"version":"0.16.10","stable":true},"intermediary":{"version":"1.21.1"}},{"loader":{"version":"0.17.1","stable":false},"intermediary":{"version":"1.21.1"}}]"#.utf8)
        ])
        defer { fixture.close() }
        let client = HTTPClient(session: fixture.session, routing: NetworkRouting(source: .official))
        let releases = try await LoaderRelease.sorted(LoaderReleaseCatalog.releases(.fabric, game: "1.21.1", client: client))
        #expect(releases.map(\.version) == ["0.16.10", "0.16.9", "0.17.1", "0.17.0-beta.2"])
        #expect(releases.map(\.channel) == [.stable, .stable, .preview, .beta])
        #expect(try await LoaderReleaseCatalog.releases(.fabric, game: "1.12.2", client: client).isEmpty)
        #expect(!fixture.requests.contains { $0.url.path.hasSuffix("loader/1.12.2") })
    }

    @Test func quiltUnorderedVersionsAndForgeMinecraftPrefixes() async throws {
        let fixture = EndpointHTTPFixture([
            "meta.quiltmc.org/v3/versions/game": Data(#"[{"version":"1.21.1"}]"#.utf8),
            "meta.quiltmc.org/v3/versions/loader/1.21.1": Data(#"[{"loader":{"version":"0.20.0-beta.9"},"hashed":{"version":"1.21.1"}},{"loader":{"version":"0.28.1"},"intermediary":{"version":"1.21.1"}},{"loader":{"version":"0.29.0-beta.10"},"intermediary":{"version":"1.21.1"}}]"#.utf8),
            "maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml": Data("<metadata><versioning><versions><version>1.12.2-14.23.5.2860</version><version>1.12-14.21.1.2387</version><version>1.12.2-14.23.5.2859</version></versions></versioning></metadata>".utf8),
            "maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml": Data("<metadata><versioning><versions><version>21.1.50-beta</version><version>21.1.49</version><version>21.10.1</version><version>21.0.50</version></versions></versioning></metadata>".utf8)
        ])
        defer { fixture.close() }
        let client = HTTPClient(session: fixture.session, routing: NetworkRouting(source: .official))
        let quilt = try await LoaderRelease.sorted(LoaderReleaseCatalog.releases(.quilt, game: "1.21.1", client: client))
        #expect(quilt.map(\.version) == ["0.28.1", "0.29.0-beta.10", "0.20.0-beta.9"])
        #expect(try await ForgeCatalog.versions(loader: .forge, game: "1.12.2", client: client) == ["14.23.5.2860", "14.23.5.2859"])
        #expect(try await ForgeCatalog.versions(loader: .neoforge, game: "1.21.1", client: client) == ["21.1.49", "21.1.50-beta"])
        #expect(LoaderRelease(version: "HD_U_G6_pre1").channel == .preview)
        #expect(LoaderRelease(version: "0.1.0-alpha.2").channel == .alpha)
        #expect(LoaderRelease(version: "0.1.0-rc.1").channel == .rc)
        #expect(LoaderRelease(version: "1.12.2-SNAPSHOT").channel == .snapshot)
    }

    @Test(arguments: ["26.1", "26.1.2", "26.2", "26.3-pre-2"])
    func unobfuscatedGamesAcceptPlaceholderAndAbsentMappings(game: String) async throws {
        let games = try JSONSerialization.data(withJSONObject: [["version": game]])
        let fixture = EndpointHTTPFixture([
            "meta.fabricmc.net/v2/versions/game": games,
            "meta.fabricmc.net/v2/versions/loader/" + game: Data(#"""
                [
                    {"loader":{"version":"0.19.5","stable":true},"intermediary":{"version":"0.0.0"}},
                    {"loader":{"version":"0.19.6-beta.1","stable":false},"intermediary":{"version":"0.0.0"}},
                    {"loader":{"version":"0.16.10"},"intermediary":{"version":"1.21.1"}},
                    {"loader":{"version":"0.16.9"}}
                ]
                """#.utf8),
            "meta.quiltmc.org/v3/versions/game": games,
            "meta.quiltmc.org/v3/versions/loader/" + game: Data(#"""
                [
                    {"loader":{"version":"0.30.0-beta.1"}},
                    {"loader":{"version":"0.29.2"},"intermediary":null,"hashed":null},
                    {"loader":{"version":"0.28.1"},"hashed":{"version":"1.21.1"}},
                    {"loader":{"version":"0.28.0"},"intermediary":{"version":"1.21.1"}}
                ]
                """#.utf8)
        ])
        defer { fixture.close() }
        let client = HTTPClient(session: fixture.session, routing: NetworkRouting(source: .official))
        let fabric = try await LoaderRelease.sorted(LoaderReleaseCatalog.releases(.fabric, game: game, client: client))
        #expect(fabric.map(\.version) == ["0.19.5", "0.19.6-beta.1"])
        #expect(fabric.map(\.channel) == [.stable, .beta])
        let quilt = try await LoaderRelease.sorted(LoaderReleaseCatalog.releases(.quilt, game: game, client: client))
        #expect(quilt.map(\.version) == ["0.29.2", "0.30.0-beta.1"])
        #expect(quilt.map(\.channel) == [.stable, .beta])
        for loader in [LoaderKind.fabric, .quilt] {
            #expect(try await LoaderReleaseCatalog.releases(loader, game: "unknown-version", client: client).isEmpty)
        }
        #expect(!fixture.requests.contains { $0.url.path.hasSuffix("loader/unknown-version") })
    }

    @Test func legacyFabricStillRequiresMatchingMappings() async throws {
        let fixture = EndpointHTTPFixture([
            "meta.legacyfabric.net/v2/versions/game": Data(#"[{"version":"1.8.9"}]"#.utf8),
            "meta.legacyfabric.net/v2/versions/loader/1.8.9": Data(#"""
                [
                    {"loader":{"version":"0.16.10"},"intermediary":{"version":"1.8.9"}},
                    {"loader":{"version":"0.16.9"},"intermediary":{"version":"0.0.0"}},
                    {"loader":{"version":"0.16.8"}}
                ]
                """#.utf8)
        ])
        defer { fixture.close() }
        let client = HTTPClient(session: fixture.session, routing: NetworkRouting(source: .official))
        #expect(try await LoaderReleaseCatalog.releases(.legacyfabric, game: "1.8.9", client: client).map(\.version) == ["0.16.10"])
        #expect(try await LoaderReleaseCatalog.releases(.legacyfabric, game: "26.1", client: client).isEmpty)
        #expect(!fixture.requests.contains { $0.url.path.hasSuffix("loader/26.1") })
    }

    @Test func combinationsRejectConflictsAndPreserveAllComponentsInStateAndPacks() throws {
        let selections: [LoaderSelection] = [.init(loader: .optifine, version: "HD_U_G5"), .init(loader: .forge, version: "14.23.5.2860")]
        try LoaderCompatibility.validate(selections, game: "1.12.2")
        for loaders: [LoaderKind] in [[.fabric, .forge], [.forge, .neoforge], [.quilt, .optifine], [.liteloader, .optifine], [.forge, .liteloader, .optifine], [.forge, .forge], [.vanilla]] {
            #expect(LoaderCompatibility.combinationIssue(loaders, game: "1.12.2") != nil)
        }
        #expect(LoaderCompatibility.combinationIssue([.forge, .optifine], game: "1.20.1") == nil)
        #expect(LoaderCompatibility.combinationIssue([.forge, .optifine], game: "1.21.11") == nil)
        var instance = GameInstance(name: "Combined", gameVersion: "1.12.2")
        instance.setLoaderSelections(selections)
        #expect(instance.loader == .forge && instance.loaderSelections.map(\.loader) == [.forge, .optifine])
        let decoded = try JSONDecoder().decode(GameInstance.self, from: JSONEncoder().encode(instance))
        #expect(decoded.loaderSelections == instance.loaderSelections)
        let pack = try JSONDecoder().decode(PortableInstance.self, from: JSONEncoder().encode(PortableInstance(instance)))
        #expect(try pack.instance().loaderSelections == instance.loaderSelections)
        var edited = instance; edited.setLoaderSelections([.init(loader: .forge, version: "14.23.5.2860")])
        #expect(throws: (any Error).self) { try edited.applyingInstallation(instance, requested: instance) }
    }

    @Test func combinedLaunchWrapperPreservesArgumentsAndOrdersTweakers() throws {
        var base = VersionManifest(id: "1.12.2", mainClass: "net.minecraft.launchwrapper.Launch", libraries: [])
        base.minecraftArguments = "--username Player --gameDir '/path with spaces' --tweakClass net.minecraftforge.fml.common.launcher.FMLTweaker --tweakClass com.mumfrey.liteloader.launch.LiteLoaderTweaker --tweakClass optifine.OptiFineTweaker --tweakClass custom.OtherTweaker"
        let merged = try LoaderLaunchArguments.combining(base, loaders: [.forge, .liteloader, .optifine])
        let arguments = try ArgumentTokenizer.split(merged.minecraftArguments!)
        #expect(arguments.prefix(4) == ["--username", "Player", "--gameDir", "/path with spaces"])
        #expect(arguments.suffix(6) == ["--tweakClass", "com.mumfrey.liteloader.launch.LiteLoaderTweaker", "--tweakClass", "optifine.OptiFineForgeTweaker", "--tweakClass", "net.minecraftforge.fml.common.launcher.FMLTweaker"])
        #expect(arguments.contains("custom.OtherTweaker"))
        #expect(!arguments.contains("optifine.OptiFineTweaker"))
        #expect(try LoaderLaunchArguments.combining(merged, loaders: [.forge, .liteloader, .optifine]).minecraftArguments == merged.minecraftArguments)
        base.mainClass = "custom.UnknownLauncher"
        #expect(throws: (any Error).self) { try LoaderLaunchArguments.combining(base, loaders: [.forge, .optifine]) }
    }
}
