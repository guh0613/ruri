import CryptoKit
import Foundation
import Testing
@testable import RuriCore

struct AssetIndexInstallationTests {
    private struct Fixture: Sendable {
        let root: URL
        let repository: URL
        let source: URL
        let paths: LauncherPaths
        let asset = Data("updated translation".utf8)
        let previous = Data(#"{"objects":{}}"#.utf8)
        let index: Data
        var hash: String { Self.hash(index) }
        var indexFile: URL { repository.appendingPathComponent("assets/indexes/5.json") }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-asset-index-" + UUID().uuidString)
            repository = root.appendingPathComponent("Minecraft"); source = root.appendingPathComponent("Pack")
            index = try JSONEncoder().encode(AssetObjects(objects: ["minecraft/lang/example.json": .init(hash: Self.hash(asset), size: Int64(asset.count))], virtual: true, map_to_resources: nil))
            try FileManager.default.createDirectory(at: repository.appendingPathComponent("assets/indexes"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: source.appendingPathComponent("minecraft"), withIntermediateDirectories: true)
            try previous.write(to: repository.appendingPathComponent("assets/indexes/5.json"))
            let instance = GameInstance(name: "Pack", gameVersion: "1.20.1")
            try JSONEncoder().encode(PortableInstance(instance)).write(to: source.appendingPathComponent("ruri-instance.json"))
            let base = LauncherPaths(root: root.appendingPathComponent("Ruri"))
            paths = base.configured(with: try MinecraftFolderStore.add(name: "Minecraft", url: repository, paths: base))
        }

        static func hash(_ data: Data) -> String { Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        func http(index replacement: Data? = nil) -> EndpointHTTPFixture {
            let assetHash = Self.hash(asset)
            return EndpointHTTPFixture([
                "fixture.invalid/5.json": replacement ?? index,
                "resources.download.minecraft.net/\(assetHash.prefix(2))/\(assetHash)": asset
            ])
        }
        func downloader(_ http: EndpointHTTPFixture) -> DownloadManager {
            DownloadManager(configuration: http.session.configuration, retryDelay: .zero, routing: NetworkRouting(source: .official))
        }
        func manifest(_ instance: GameInstance) -> VersionManifest {
            VersionManifest(id: instance.repositoryVersionID ?? instance.gameVersion, mainClass: "example.Main", jar: instance.repositoryVersionID,
                            arguments: .init(game: [.text("--assetIndex"), .text("${assets_index_name}"), .text("--gameAssets"), .text("${game_assets}")], jvm: nil),
                            libraries: [], assetIndex: .init(id: "5", url: URL(string: "https://fixture.invalid/5.json")!, sha1: hash, size: Int64(index.count)))
        }
        func install(_ instance: GameInstance, at location: LauncherPaths, downloader: DownloadManager) async throws -> GameInstance {
            try location.prepareInstance(instance.id)
            let client = try location.clientJar(instance.repositoryVersionID ?? instance.gameVersion, instance: instance)
            try FileManager.default.createDirectory(at: client.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("client".utf8).write(to: client)
            let manifest = manifest(instance)
            try await GameInstaller(paths: location, downloader: downloader)
                .prepareFiles(manifest, instance: instance, concurrency: 2) { _ in }
            try JSONEncoder().encode(manifest).write(to: location.manifest(instance.id))
            var result = instance; result.installed = true; return result
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func importReplacesAStaleSharedIndexAndReusesItForLaunchAndRepair() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let http = f.http(); defer { http.close() }
        let downloader = f.downloader(http)
        let transfer = InstanceTransfer(paths: f.paths), prepared = try await transfer.prepare(f.source)
        let installed = try await transfer.install(prepared, name: "Pack", installing: { instance, location in
            try await f.install(instance, at: location, downloader: downloader)
        })
        let paths = f.paths.configured(with: try StateStore.load(f.paths))
        let installer = GameInstaller(paths: paths, downloader: downloader)
        let manifest = try await installer.loadManifest(installed)
        let id = try #require(manifest.assetIndex?.id)
        #expect(id == "5")
        #expect(try Data(contentsOf: f.indexFile) == f.index)
        let java = JavaRuntime(path: "/fixture/java", version: "17", major: 17, architecture: GameInstaller.architecture(for: manifest), vendor: "Fixture")
        let plan = try LaunchBuilder.build(instance: installed, manifest: manifest, java: java, account: Account(username: "Player"), paths: paths)
        let argument = try #require(plan.arguments.firstIndex(of: "--assetIndex"))
        #expect(plan.arguments[argument + 1] == id)
        let virtual = f.repository.appendingPathComponent("assets/virtual/\(id)")
        #expect(plan.arguments.contains(virtual.path))
        #expect(try Data(contentsOf: virtual.appendingPathComponent("minecraft/lang/example.json")) == f.asset)
        let requestCount = http.requests.count
        // A second import should reuse the same verified index and asset objects.
        _ = try await transfer.install(prepared, name: "Another Pack", installing: { instance, location in
            try await f.install(instance, at: location, downloader: downloader)
        })
        #expect(http.requests.count == requestCount)
        #expect(try Data(contentsOf: f.indexFile) == f.index)
        // Repair refreshes an outdated shared index without changing the manifest's ID.
        try f.previous.write(to: f.indexFile)
        try await installer.repair(installed) { _ in }
        #expect(http.requests.count == requestCount + 1)
        #expect(try Data(contentsOf: f.indexFile) == f.index)
        #expect(try await installer.loadManifest(installed).assetIndex?.id == "5")
        await transfer.discard(prepared)
    }

    @Test(arguments: ["bad checksum", "download failure", "library conflict"])
    func failedVerificationStillProtectsExistingFiles(_ failure: String) async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let http = failure == "download failure" ? EndpointHTTPFixture([:]) : f.http(index: failure == "bad checksum" ? Data(repeating: 0, count: f.index.count) : nil)
        defer { http.close() }
        let downloader = f.downloader(http)
        let library = f.repository.appendingPathComponent("libraries/example.jar")
        if failure == "library conflict" {
            try FileManager.default.createDirectory(at: library.deletingLastPathComponent(), withIntermediateDirectories: true)
            try f.previous.write(to: library)
        }
        let transfer = InstanceTransfer(paths: f.paths), prepared = try await transfer.prepare(f.source)
        await #expect(throws: RepositoryImportFailure.self) {
            try await transfer.install(prepared, name: "Pack", installing: { instance, location in
                let client = try location.clientJar(instance.repositoryVersionID!, instance: instance)
                try Data("client".utf8).write(to: client)
                var manifest = f.manifest(instance)
                if failure == "library conflict" {
                    manifest.libraries = [.init(name: "example:library:1", downloads: .init(artifact: .init(path: "example.jar", url: URL(string: "https://fixture.invalid/library.jar"), sha1: f.hash)), rules: nil, natives: nil, extract: nil)]
                }
                try await GameInstaller(paths: location, downloader: downloader)
                    .prepareFiles(manifest, instance: instance, concurrency: 2) { _ in }
                Issue.record("Conflicting or unverified files must not be accepted")
                throw CancellationError()
            })
        }
        #expect(try Data(contentsOf: f.indexFile) == f.previous)
        #expect(try StateStore.load(f.paths).instances.isEmpty)
        if failure == "library conflict" { #expect(try Data(contentsOf: library) == f.previous) }
        await transfer.discard(prepared)
    }

    @Test func componentInstallationUpdatesASharedIndexThroughAnAssetsAlias() async throws {
        let f = try Fixture(); defer { f.cleanup() }
        let work = LauncherPaths(root: f.root.appendingPathComponent("component-work"))
        try work.prepare()
        try FileManager.default.removeItem(at: work.assets)
        try FileManager.default.createSymbolicLink(at: work.assets, withDestinationURL: f.repository.appendingPathComponent("assets"))
        let instance = GameInstance(name: "Component", gameVersion: "1.20.1")
        try work.prepareInstance(instance.id)
        let client = try work.clientJar(instance.gameVersion, instance: instance)
        try FileManager.default.createDirectory(at: client.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("client".utf8).write(to: client)
        let http = f.http(); defer { http.close() }
        try await GameInstaller(paths: work, downloader: f.downloader(http), protectExistingFiles: true)
            .prepareFiles(f.manifest(instance), instance: instance, concurrency: 2) { _ in }
        #expect(try Data(contentsOf: f.indexFile) == f.index)
    }
}
