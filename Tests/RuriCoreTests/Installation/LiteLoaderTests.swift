import Foundation
import Testing
@testable import RuriCore

struct LiteLoaderTests {
    @Test func catalogBuildsPreserveLegacyArgumentsAndVerifyArtifacts() throws {
        let json = Data(#"{"repo":{"url":"http://dl.liteloader.com/versions/"},"artefacts":{"com.mumfrey:liteloader":{"first":{"version":"1.7.10_00","file":"liteloader-1.7.10_00.jar","tweakClass":"com.mumfrey.liteloader.launch.LiteLoaderTweaker","libraries":[]},"last":{"version":"1.7.10_04","file":"liteloader-1.7.10_04.jar","tweakClass":"com.mumfrey.liteloader.launch.LiteLoaderTweaker","libraries":[{"name":"net.minecraft:launchwrapper:1.11"}],"md5":"5d41402abc4b2a76b9719d911017c592"},"latest":{"version":"1.7.10_04","file":"liteloader-1.7.10.jar","tweakClass":"com.mumfrey.liteloader.launch.LiteLoaderTweaker","libraries":[]}}}}"#.utf8)
        let entry = try JSONDecoder().decode(LiteLoaderCatalog.Game.self, from: json)
        let releases = try LiteLoaderCatalog.stableReleases(entry, game: "1.7.10")
        #expect(releases.map(\.version) == ["1.7.10_04", "1.7.10_00"])
        #expect(releases[0].aliases == ["1.7.10"])
        var base = VersionManifest(id: "1.7.10", mainClass: "net.minecraft.client.main.Main", libraries: [])
        base.minecraftArguments = "--username ${auth_player_name} --gameDir ${game_directory}"
        let child = try releases[0].profile(game: "1.7.10", base: base)
        let merged = base.merging(child: child)
        #expect(merged.mainClass == "net.minecraft.launchwrapper.Launch")
        #expect(try ArgumentTokenizer.split(merged.minecraftArguments!) == ["--username", "${auth_player_name}", "--gameDir", "${game_directory}", "--tweakClass", "com.mumfrey.liteloader.launch.LiteLoaderTweaker"])
        let artifact = try #require(child.libraries.last?.downloads?.artifact)
        #expect(artifact.url?.absoluteString == "https://dl.liteloader.com/versions/com/mumfrey/liteloader/1.7.10/liteloader-1.7.10_04.jar")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("hello".utf8).write(to: file)
        let decoded = try JSONDecoder().decode(Artifact.self, from: JSONEncoder().encode(artifact))
        #expect(DownloadManager.valid(file, item: DownloadItem(decoded, to: file)))
        try Data("modified".utf8).write(to: file)
        #expect(!DownloadManager.valid(file, item: DownloadItem(decoded, to: file)))
        let metadata = Data("<metadata><versioning><snapshot><timestamp>20171128.144431</timestamp><buildNumber>4</buildNumber></snapshot></versioning></metadata>".utf8)
        let snapshot = try LiteLoaderCatalog.snapshotRelease(releases[0].build, game: "1.12.2", metadata: metadata)
        #expect(snapshot.version == "1.12.2-20171128.144431-4")
        #expect(snapshot.aliases == ["1.12.2-SNAPSHOT", "20171128.144431-4"])
        #expect(snapshot.url.lastPathComponent == "liteloader-1.12.2-20171128.144431-4-release.jar")
        let modern = try snapshot.profile(game: "1.12.2", base: VersionManifest(id: "1.12.2", libraries: []), sha1: "d71bcab251d1b36e4827c8f7e7499596a1bd7c62")
        #expect(modern.minecraftArguments == nil && modern.arguments?.game?.count == 2)
        #expect(modern.libraries.last?.downloads?.artifact?.md5 == nil)
        #expect(throws: (any Error).self) { try LiteLoaderCatalog.snapshotRelease(releases[0].build, game: "1.12.2", metadata: Data("<metadata/>".utf8)) }
    }

    @Test func importsLiteLoaderPacksAndManagesLiteMods() async throws {
        let helper = HMCLPackTests(), (paths, source) = try helper.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try helper.json(["name": "Lite pack", "gameVersion": "1.12.2"], to: "modpack.json", in: source)
        try helper.json(["jar": "1.12.2", "libraries": [["name": "com.mumfrey:liteloader:1.12.2-SNAPSHOT"]], "minecraftArguments": "--tweakClass com.mumfrey.liteloader.launch.LiteLoaderTweaker"], to: "minecraft/pack.json", in: source)
        let transfer = InstanceTransfer(paths: paths), prepared = try await transfer.prepare(source)
        #expect(prepared.instance.loader == .liteloader && prepared.instance.loaderVersion == "1.12.2-SNAPSHOT")
        let instance = try await transfer.install(prepared, name: "Lite pack") { $0 }
        await transfer.discard(prepared)
        let modSource = paths.cache.appendingPathComponent("mod-source")
        try FileManager.default.createDirectory(at: modSource, withIntermediateDirectories: true)
        try helper.json(["name": "example", "displayName": "Example Lite Mod", "version": "2.0", "mcversion": "1.12.2"], to: "litemod.json", in: modSource)
        let mod = paths.cache.appendingPathComponent("example.litemod")
        try SafeArchive.create(from: modSource, to: mod)
        let manager = ContentManager(paths: paths, instanceID: instance.id)
        try await manager.importFiles([mod], kind: .mod)
        let first = try #require(await manager.scan(.mod).first)
        #expect(first.title == "Example Lite Mod" && first.modID == "example" && first.version == "2.0")
        try await manager.setEnabled(false, file: first)
        #expect(try await manager.scan(.mod).first?.enabled == false)
        await #expect(throws: (any Error).self) { try await manager.importFiles([mod], kind: .mod) }
        for format in [InstanceExportFormat.ruri, .mcbbs] {
            let zip = paths.cache.appendingPathComponent(format.rawValue + ".zip")
            try await transfer.export(instance, to: zip, format: format)
            let pack = try await transfer.prepare(zip)
            #expect(pack.instance.loader == .liteloader && pack.instance.loaderVersion == "1.12.2-SNAPSHOT")
            let restored = try await transfer.install(pack, name: "Restored") { $0 }
            let files = try await ContentManager(paths: paths, instanceID: restored.id).scan(.mod)
            #expect(files.count == 1 && files[0].filename == "example.litemod" && !files[0].enabled)
            await transfer.discard(pack)
        }
        try FileManager.default.removeItem(at: source.appendingPathComponent("modpack.json"))
        try helper.json(["formatVersion": 1, "components": [["uid": "net.minecraft", "version": "1.12.2"], ["uid": "com.mumfrey.liteloader", "version": "1.12.2-SNAPSHOT"]]], to: "mmc-pack.json", in: source)
        let prism = try await transfer.prepare(source)
        #expect(prism.instance.loader == .liteloader)
        await transfer.discard(prism)
        var combined = instance; combined.installed = true
        combined.repositoryComponents = [.init(name: "Forge", version: "14.23.5.2860"), .init(name: "LiteLoader", version: "1.12.2-SNAPSHOT")]
        #expect(InstanceComponents.unavailableReason(combined)?.contains("多个加载器") == true)
    }
}
