import CryptoKit
import Foundation
import Testing
@testable import RuriCore

struct ImportedMinecraftInstallationTests {
    private struct Fixture {
        let root: URL
        let paths: LauncherPaths
        let instance: GameInstance
        let target: GameDirectory
        let manifest: VersionManifest
        let resources: GameResourcePaths
        let client = Data("locally modified client".utf8)
        let relativeLibrary = "fixture/bootstrap/1/bootstrap-1.jar"
        let asset = Data("local resource".utf8)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-local installation-\(UUID())")
            let base = LauncherPaths(root: root.appendingPathComponent("Data"))
            let targetURL = root.appendingPathComponent("Other collection")
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            target = try GameDirectory.create(name: "Other", at: targetURL, paths: base)
            var game = GameInstance(name: "Custom local game", gameVersion: "1.21.1", loader: .neoforge, loaderVersion: "21.1.250")
            game.importedInstallation = .init(sourceVersionID: "My local version", components: [.init(name: "NeoForge", version: "21.1.250")])
            game.installed = true
            instance = game
            var state = PersistentState(); state.instances = [game]; state.gameDirectories = [target]
            paths = base.configured(with: try StateStore.save(state, to: base))
            resources = try paths.resources(for: game)
            let index = try JSONSerialization.data(withJSONObject: ["map_to_resources": true, "objects": ["sound/local.ogg": ["hash": Self.hash(asset), "size": asset.count]]])
            let library = Data("locally modified bootstrap".utf8)
            let logging = Data("local log configuration".utf8)
            manifest = try JSONDecoder().decode(VersionManifest.self, from: JSONSerialization.data(withJSONObject: [
                "id": "My local version", "jar": "local-client", "mainClass": "cpw.mods.bootstraplauncher.BootstrapLauncher",
                "javaVersion": ["majorVersion": 21],
                "downloads": ["client": ["sha1": Self.hash(client), "size": client.count]],
                "libraries": [["name": "fixture:bootstrap:1", "downloads": ["artifact": ["path": relativeLibrary, "sha1": Self.hash(library), "size": library.count]]]],
                "generatedLibraries": [["path": "fixture/generated.jar", "size": 9]],
                "assetIndex": ["id": "local-assets", "url": "https://fixture.invalid/index.json", "sha1": Self.hash(index), "size": index.count],
                "logging": ["client": ["argument": "-Dlog4j.configurationFile=${path}", "file": ["id": "local.xml", "url": "https://fixture.invalid/local.xml", "sha1": Self.hash(logging), "size": logging.count]]],
                "arguments": ["jvm": ["-cp", "${classpath}", "-p", "${library_directory}/" + relativeLibrary, "-Dlocal.customization=preserved"],
                              "game": ["--gameDir", "${game_directory}", "--assetsDir", "${assets_root}", "--legacyAssets", "${game_assets}"]]
            ]))
            try write(client, "versions/local-client/local-client.jar", in: resources.root)
            try write(library, "libraries/" + relativeLibrary, in: resources.root)
            try write(Data("generated".utf8), "libraries/fixture/generated.jar", in: resources.root)
            try write(index, "assets/indexes/local-assets.json", in: resources.root)
            try write(logging, "assets/log_configs/local.xml", in: resources.root)
            let hash = Self.hash(asset)
            try write(asset, "assets/objects/\(hash.prefix(2))/\(hash)", in: resources.root)
            try write(JSONEncoder().encode(manifest), "version.json", in: paths.instance(game.id))
            try write(Data("game options".utf8), "options.txt", in: paths.game(game.id))
            // Deliberately incompatible files under the same shared names.
            for relative in ["versions/local-client/local-client.jar", "libraries/" + relativeLibrary, "libraries/fixture/generated.jar", "assets/indexes/local-assets.json", "assets/log_configs/local.xml"] {
                try write(Data("shared file belongs to other games".utf8), relative, in: paths.root)
            }
        }
        static func hash(_ data: Data) -> String { Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        func write(_ data: Data, _ relative: String, in directory: URL) throws {
            let file = directory.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        func plan(_ game: GameInstance, paths: LauncherPaths) throws -> LaunchPlan {
            let java = JavaRuntime(path: "/fixture/java", version: "21", major: 21, architecture: GameInstaller.architecture(for: manifest), vendor: "Fixture")
            return try LaunchBuilder.build(instance: game, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func launchUsesLocalClientLibrariesAndAssetsWithoutChangingOrdinaryInstances() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let plan = try f.plan(f.instance, paths: f.paths)
        let classIndex = try #require(plan.arguments.firstIndex(of: "-cp"))
        let moduleIndex = try #require(plan.arguments.firstIndex(of: "-p"))
        let classes = plan.arguments[classIndex + 1].split(separator: ":").map(String.init)
        #expect(classes == [f.resources.libraries.appendingPathComponent(f.relativeLibrary).path, f.resources.versions.appendingPathComponent("local-client/local-client.jar").path])
        #expect(classes.contains(plan.arguments[moduleIndex + 1]))
        #expect(plan.arguments.contains(f.resources.assets.path))
        #expect(plan.arguments.contains(f.resources.assets.appendingPathComponent("virtual/local-assets").path))
        #expect(plan.arguments.contains("-Dlog4j.configurationFile=\(f.resources.assets.path)/log_configs/local.xml"))
        #expect(plan.arguments.contains("-Dlocal.customization=preserved"))
        let ordinary = GameInstance(name: "New game", gameVersion: "1.21.1")
        #expect(try f.paths.resources(for: ordinary).root == f.paths.root)
        // A serialized monitor snapshot must resolve the same installation.
        let monitor = try JSONDecoder().decode(LauncherPaths.self, from: JSONEncoder().encode(f.paths.monitorSnapshot(for: f.instance.id)))
        #expect(try f.plan(f.instance, paths: monitor).arguments == plan.arguments)
    }

    @Test func missingLocalFilesNeverFallBackToSharedNames() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        try FileManager.default.removeItem(at: f.resources.versions.appendingPathComponent("local-client/local-client.jar"))
        #expect(throws: (any Error).self) { try f.plan(f.instance, paths: f.paths) }
        let http = EndpointHTTPFixture([:]); defer { http.close() }
        let downloader = DownloadManager(configuration: http.session.configuration, retryDelay: .zero)
        await #expect(throws: (any Error).self) { try await GameInstaller(paths: f.paths, downloader: downloader).repair(f.instance) { _ in } }
        #expect(http.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.resources.versions.appendingPathComponent("local-client/local-client.jar").path))
    }

    @Test func repairRetainsTheLocalForgeManifestAndMapsItsOwnLegacyAssets() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let manifestBytes = try Data(contentsOf: f.paths.manifest(f.instance.id))
        let shared = try [f.paths.versions, f.paths.libraries, f.paths.assets].map { ($0, try FileTreeManifest.capture(in: $0)) }
        let native = f.resources.libraries.appendingPathComponent("fixture/native.jar")
        try ArchiveAndLaunchTests().makeZip(native, entries: [("fixture.dylib", Data("native".utf8), .file)])
        var manifest = f.manifest
        manifest.libraries.append(try JSONDecoder().decode(Library.self, from: Data(#"{"name":"fixture:native:1","natives":{"osx":"natives-osx"},"downloads":{"classifiers":{"natives-osx":{"path":"fixture/native.jar"}}}}"#.utf8)))
        try JSONEncoder().encode(manifest).write(to: f.paths.manifest(f.instance.id))
        let expected = try Data(contentsOf: f.paths.manifest(f.instance.id))
        #expect(expected != manifestBytes)
        let http = EndpointHTTPFixture([:]); defer { http.close() }
        let service = GameInstaller(paths: f.paths, downloader: DownloadManager(configuration: http.session.configuration, retryDelay: .zero))
        try await service.repair(f.instance) { _ in }
        #expect(http.requests.isEmpty)
        #expect(try Data(contentsOf: f.paths.manifest(f.instance.id)) == expected)
        #expect(try Data(contentsOf: f.paths.game(f.instance.id).appendingPathComponent("resources/sound/local.ogg")) == f.asset)
        #expect(try String(contentsOf: f.paths.instance(f.instance.id).appendingPathComponent("natives/fixture.dylib"), encoding: .utf8) == "native")
        for (root, receipt) in shared { try receipt.requireMatch(in: root) }
        try FileManager.default.removeItem(at: f.paths.game(f.instance.id).appendingPathComponent("resources"))
        try await service.prepareRunDirectory(f.instance, manifest: manifest)
        #expect(try Data(contentsOf: f.paths.game(f.instance.id).appendingPathComponent("resources/sound/local.ogg")) == f.asset)
    }

    @Test func repairDownloadsMissingRecoverableFilesIntoTheLocalInstallation() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        var manifest = f.manifest
        manifest.downloads = ["client": .init(url: URL(string: "https://fixture.invalid/client.jar"), sha1: Fixture.hash(f.client), size: Int64(f.client.count))]
        try JSONEncoder().encode(manifest).write(to: f.paths.manifest(f.instance.id))
        let client = f.resources.versions.appendingPathComponent("local-client/local-client.jar")
        try FileManager.default.removeItem(at: client)
        let shared = try FileTreeManifest.capture(in: f.paths.versions)
        let http = EndpointHTTPFixture(["fixture.invalid/client.jar": f.client]); defer { http.close() }
        try await GameInstaller(paths: f.paths, downloader: DownloadManager(configuration: http.session.configuration, retryDelay: .zero)).repair(f.instance) { _ in }
        #expect(http.requests.map(\.url.path) == ["/client.jar"])
        #expect(try Data(contentsOf: client) == f.client)
        try shared.requireMatch(in: f.paths.versions)
    }

    @Test func copyingAndMovingCarryResourcesAndRebindEveryLaunchPath() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let copier = InstanceCopier(paths: f.paths)
        let preview = try await copier.preview(instanceID: f.instance.id, name: "Local copy", directoryID: f.target.id)
        let result = try await copier.copy(preview), current = f.paths.configured(with: result.state)
        let copy = try #require(result.state.instances.first { $0.id == preview.copy.id })
        #expect(copy.importedInstallation == f.instance.importedInstallation)
        let copied = try current.resources(for: copy)
        #expect(copied.root.path.hasPrefix(f.target.url.path + "/"))
        let receipt = try FileTreeManifest.capture(in: f.resources.root)
        try receipt.requireMatch(in: copied.root)
        let copyPlan = try f.plan(copy, paths: current)
        #expect(copyPlan.arguments.joined(separator: " ").contains(copied.root.path))
        #expect(!copyPlan.arguments.joined(separator: " ").contains(f.resources.root.path))
        try f.write(Data("edited independent copy".utf8), "libraries/" + f.relativeLibrary, in: copied.root)
        try receipt.requireMatch(in: f.resources.root)

        let mover = InstanceMover(paths: current)
        let move = try await mover.preview(instanceID: f.instance.id, directoryID: f.target.id)
        let movedResult = try await mover.move(move), movedPaths = f.paths.configured(with: movedResult.state)
        let moved = try #require(movedResult.state.instances.first { $0.id == f.instance.id })
        let movedResources = try movedPaths.resources(for: moved)
        try receipt.requireMatch(in: movedResources.root)
        #expect(!FileManager.default.fileExists(atPath: f.resources.root.path))
        let movedPlan = try f.plan(moved, paths: movedPaths)
        #expect(movedPlan.arguments.joined(separator: " ").contains(movedResources.root.path))
        #expect(!movedPlan.arguments.joined(separator: " ").contains(f.resources.root.path))
    }

    @Test func refusesIncompleteCopiesAndLossyPortableExports() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let destination = f.root.appendingPathComponent("existing.zip"), existing = Data("keep this file".utf8)
        try existing.write(to: destination)
        for format in InstanceExportFormat.allCases {
            await #expect(throws: (any Error).self) { try await InstanceTransfer(paths: f.paths).export(f.instance, to: destination, format: format) }
            #expect(try Data(contentsOf: destination) == existing)
        }
        try FileManager.default.removeItem(at: f.resources.root)
        await #expect(throws: (any Error).self) { try await InstanceCopier(paths: f.paths).preview(instanceID: f.instance.id, name: "Incomplete", directoryID: f.target.id) }
    }

    @Test func redirectedLocalResourceFoldersCannotWriteIntoSharedStorage() throws {
        let f = try Fixture(); defer { f.cleanup() }
        for (owned, shared) in [(f.resources.assets, f.paths.assets), (f.resources.libraries, f.paths.libraries), (f.resources.versions, f.paths.versions)] {
            try FileManager.default.removeItem(at: owned)
            try FileManager.default.createSymbolicLink(at: owned, withDestinationURL: shared)
            #expect(throws: (any Error).self) { try f.paths.resources(for: f.instance) }
            try FileManager.default.removeItem(at: owned)
        }
        try FileManager.default.removeItem(at: f.resources.root)
        try FileManager.default.createSymbolicLink(at: f.resources.root, withDestinationURL: f.paths.root)
        #expect(throws: (any Error).self) { try f.paths.resources(for: f.instance) }
    }
}
