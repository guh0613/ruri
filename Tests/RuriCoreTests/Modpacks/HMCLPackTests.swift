import Foundation
import CryptoKit
import Testing
import ZIPFoundation
@testable import RuriCore

private final class MCBBSFileProtocol: URLProtocol, @unchecked Sendable {
    static let body = Data("remote pack config".utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, url.host == "mcbbs.ruri.test", url.path == "/pack/overrides/config/中文 file.txt" else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Length": String(Self.body.count)])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct HMCLPackTests {
    func setup() throws -> (LauncherPaths, URL) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        let source = paths.cache.appendingPathComponent("source"); try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        return (paths, source)
    }
    func write(_ data: Data, to path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url)
    }
    func json(_ value: Any, to path: String, in root: URL) throws { try write(JSONSerialization.data(withJSONObject: value, options: .sortedKeys), to: path, in: root) }
    func hash(_ data: Data) -> String { Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    @Test func legacyHMCLRecognizesSupportedLoadersAndOmitsPackJSON() async throws {
        let cases: [(String, String, [String: Any], LoaderKind, String?)] = [
            ("vanilla", "1.21.1", ["libraries": []], .vanilla, nil),
            ("fabric", "1.21.1", ["libraries": [["name": "net.fabricmc:fabric-loader:0.19.5"]]], .fabric, "0.19.5"),
            ("quilt", "1.21.1", ["libraries": [["name": "org.quiltmc:quilt-loader:0.29.3"]]], .quilt, "0.29.3"),
            ("forge", "1.12.2", ["libraries": [["name": "net.minecraftforge:forge:1.12.2-14.23.5.2864:universal"]]], .forge, "14.23.5.2864"),
            ("optifine", "1.12.2", ["libraries": [["name": "optifine:OptiFine:1.12.2_HD_U_G5"]]], .optifine, "HD_U_G5"),
            ("liteloader", "1.12.2", ["patches": [["id": "liteloader", "version": "1.12.2"]]], .liteloader, "1.12.2"),
            ("legacyfabric", "1.8.9", ["libraries": [["name": "net.fabricmc:fabric-loader:0.19.5"], ["name": "net.legacyfabric:intermediary:1.8.9"]]], .legacyfabric, "0.19.5"),
            ("neo", "1.21.1", ["libraries": [["name": "net.neoforged.fancymodloader:loader:4.0.0"], ["name": "net.minecraftforge:fmlloader:1.21.1-52.0.0"]], "arguments": ["game": ["--fml.neoForgeVersion", "21.1.250"]]], .neoforge, "21.1.250"),
            ("patch", "1.21.1", ["patches": [["id": "fabric", "version": "0.19.5", "libraries": [["name": "net.fabricmc:fabric-loader:0.18.0"]]]]], .fabric, "0.19.5")
        ]
        for (name, game, version, loader, loaderVersion) in cases {
            let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
            try json(["name": name, "gameVersion": game, "version": "Pack Version 2"], to: "modpack.json", in: source)
            var version = version; version["jar"] = ["id": game]
            try json(version, to: "minecraft/pack.json", in: source)
            try write(Data("options".utf8), to: "minecraft/options.txt", in: source)
            let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
            #expect(preview.format == "HMCL"); #expect(preview.instance.gameVersion == game)
            #expect(preview.instance.loader == loader); #expect(preview.instance.loaderVersion == loaderVersion)
            #expect(preview.fileCount == 1); #expect(!FileManager.default.fileExists(atPath: preview.game.appendingPathComponent("pack.json").path))
            let imported = try await transfer.install(preview, name: name) { $0 }
            #expect(try Data(contentsOf: paths.game(imported.id).appendingPathComponent("options.txt")) == Data("options".utf8))
            #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("minecraft/pack.json").path))
            await transfer.discard(preview)
        }
    }
    @Test func unsupportedHMCLComponentsAreNotSilentlyImportedAsVanilla() async throws {
        for version: [String: Any] in [
            ["patches": [["id": "fabric", "version": "1"], ["id": "forge", "version": "2"]]],
            ["mainClass": "custom.bootstrap.Main", "libraries": []]
        ] {
            let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
            try json(["name": "Unsupported", "gameVersion": "1.12.2"], to: "modpack.json", in: source)
            try json(version, to: "minecraft/pack.json", in: source)
            await #expect(throws: (any Error).self) { try await InstanceTransfer(paths: paths).prepare(source) }
        }
    }
    @Test func mcbbsExportRoundTripPreservesFilesAndLaunchSettings() async throws {
        let (paths, original) = try InstanceTransferTests().setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var instance = original; instance.extraGameArguments = "--server play.example.test"; instance.supportedJavaMajors = [21, 25]
        instance.packLibraries = try JSONDecoder().decode([Library].self, from: Data(#"[{"name":"example:custom:1","url":"https://example.test/maven/"}]"#.utf8))
        let transfer = InstanceTransfer(paths: paths); let destination = paths.cache.appendingPathComponent("mcbbs.zip")
        try await transfer.export(instance, to: destination, format: .mcbbs, details: .init(version: "2.3.4", author: "测试作者", description: "Export fixture"))
        let archive = try Archive(url: destination, accessMode: .read)
        #expect(archive["mcbbs.packmeta"] != nil); #expect(archive["manifest.json"] != nil)
        #expect(archive["overrides/config/empty.txt"]?.uncompressedSize == 0)
        #expect(archive["overrides/launcher_accounts.json"] == nil)
        let preview = try await transfer.prepare(destination)
        #expect(preview.format == "MCBBS") // must win over compatibility manifest.json
        #expect(preview.instance.memoryMB == 6144); #expect(preview.instance.width == 1600); #expect(preview.instance.height == 900)
        #expect(preview.instance.supportedJavaMajors == [21, 25]); #expect(preview.instance.packLibraries == instance.packLibraries)
        #expect(try ArgumentTokenizer.split(preview.instance.extraJVMArguments) == ArgumentTokenizer.split(instance.extraJVMArguments))
        #expect(preview.instance.extraGameArguments?.contains("play.example.test") == true)
        #expect(preview.warnings.contains { $0.contains("测试作者") })
        let sourceManifest = try #require(preview.sourceMetadata)
        #expect(try JSONDecoder().decode(MCBBSManifest.self, from: sourceManifest).version == "2.3.4")
        for file in preview.packFiles { #expect(DownloadManager.valid(try file.item(in: preview.game).destination, item: try file.item(in: preview.game))) }
        let imported = try await transfer.install(preview, name: "Imported", importJVMArguments: true) { $0 }
        #expect(try Data(contentsOf: paths.game(imported.id).appendingPathComponent("config/empty.txt")).isEmpty)
        #expect(try Data(contentsOf: paths.instance(imported.id).appendingPathComponent("source-mcbbs.packmeta")) == sourceManifest)
        await transfer.discard(preview)
        let portable = paths.cache.appendingPathComponent("portable.zip")
        try await transfer.export(imported, to: portable)
        let reopened = try await transfer.prepare(portable)
        #expect(reopened.sourceMetadata == sourceManifest); #expect(reopened.instance.packLibraries == instance.packLibraries)
        await transfer.discard(reopened)
    }
    @Test func mcbbsRemoteCompletionVerifiesFilesBeforeInstanceCreation() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let body = MCBBSFileProtocol.body
        let manifest: [String: Any] = ["manifestType": "minecraftModpack", "manifestVersion": 2, "name": "Remote", "addons": [["id": "game", "version": "1.21.1"]],
            "fileApi": "https://mcbbs.ruri.test/pack", "files": [["type": "addon", "path": "config/中文 file.txt", "hash": hash(body), "force": false]]]
        try json(manifest, to: "mcbbs.packmeta", in: source)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        #expect(preview.remoteFileCount == 1)
        await #expect(throws: (any Error).self) { try await transfer.install(preview, name: "Missing") { _ in Issue.record("Must not run installer with missing files"); throw RuriError.message("unreachable") } }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MCBBSFileProtocol.self]
        try await transfer.completeFiles(preview, downloader: DownloadManager(configuration: config, retryDelay: .zero)) { _ in }
        let imported = try await transfer.install(preview, name: "Complete") { $0 }
        #expect(try Data(contentsOf: paths.game(imported.id).appendingPathComponent("config/中文 file.txt")) == body)
        #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("overrides").path))
        await transfer.discard(preview)
    }
    @Test func mcbbsCorruptHashesAndUnsafePathsFailDuringPreview() async throws {
        for (path, expected) in [("../escape", hash(Data())), ("config/empty.txt", hash(Data("wrong".utf8)))] {
            let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
            try json(["manifestType": "minecraftModpack", "manifestVersion": 2, "name": "Bad", "addons": [["id": "game", "version": "1.21.1"]],
                      "files": [["type": "addon", "path": path, "hash": expected]]], to: "mcbbs.packmeta", in: source)
            try write(Data(), to: "overrides/config/empty.txt", in: source)
            await #expect(throws: (any Error).self) { try await InstanceTransfer(paths: paths).prepare(source) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: paths.instances.path).isEmpty)
        }
    }
    @Test func mcbbsKeepsOnlyLaunchSettingsThePackSets() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try json(["manifestType": "minecraftModpack", "manifestVersion": 2, "name": "Settings", "addons": [["id": "game", "version": "1.21.1"]], "files": [],
                  "launchInfo": ["minMemory": 6144, "javaArgument": ["-Dpack=yes"]]], to: "mcbbs.packmeta", in: source)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        let overrides = try #require(preview.instance.launchOverrides)
        #expect(overrides.memory == .init(maximumMB: 6144)); #expect(try ArgumentTokenizer.split(overrides.jvmArguments ?? "") == ["-Dpack=yes"])
        #expect(overrides.window == nil && overrides.gameArguments == nil && overrides.java == nil)
        let imported = try await transfer.install(preview, name: "Settings", importJVMArguments: false) { $0 }
        #expect(imported.launchOverrides?.jvmArguments == nil && imported.launchOverrides?.memory == .init(maximumMB: 6144))
        let global = try await transfer.install(preview.inheritingLaunchSettings([.memory]), name: "Global", importJVMArguments: true) { $0 }
        #expect(global.launchOverrides?.memory == nil && global.launchOverrides?.jvmArguments != nil)
        await transfer.discard(preview)
    }
    @Test func packsWithoutLaunchSettingsFollowGlobalSettings() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try json(["manifestType": "minecraftModpack", "manifestVersion": 2, "name": "Plain", "addons": [["id": "game", "version": "1.21.1"]], "files": []], to: "mcbbs.packmeta", in: source)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        #expect(preview.instance.launchOverrides == .init())
        var defaults = AppSettings(); defaults.defaultWindow = .init(width: 1600, height: 900)
        let resolved = preview.instance.resolvedLaunchSettings(defaults: defaults)
        #expect(resolved.memory.mode == .automatic && resolved.window.width == 1600)
        await transfer.discard(preview)
        let mmc = paths.cache.appendingPathComponent("mmc")
        try FileManager.default.createDirectory(at: mmc.appendingPathComponent(".minecraft"), withIntermediateDirectories: true)
        try json(["formatVersion": 1, "components": [["uid": "net.minecraft", "version": "1.21.1"]]], to: "mmc-pack.json", in: mmc)
        try write(Data("OverrideMemory=true\nMaxMemAlloc=6144\nOverrideWindow=false\nMinecraftWinWidth=640\n".utf8), to: "instance.cfg", in: mmc)
        let multimc = try await transfer.prepare(mmc)
        let overrides = try #require(multimc.instance.launchOverrides)
        #expect(overrides.memory == .init(maximumMB: 6144) && overrides.window == nil && overrides.jvmArguments == nil)
        await transfer.discard(multimc)
    }
    @Test func curseForceFlagControlsReplacementNotOptionality() async throws {
        let (paths, source) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try json(["manifestType": "minecraftModpack", "manifestVersion": 2, "name": "Curse", "addons": [["id": "game", "version": "1.21.1"]],
                  "files": [["type": "curse", "projectID": 1, "fileID": 10, "force": false]]], to: "mcbbs.packmeta", in: source)
        let transfer = InstanceTransfer(paths: paths); let preview = try await transfer.prepare(source)
        #expect(preview.curseForgeFiles.first?.required == true)
        await transfer.discard(preview)
        try FileManager.default.moveItem(at: source.appendingPathComponent("mcbbs.packmeta"), to: source.appendingPathComponent("manifest.json"))
        let alternate = try await transfer.prepare(source)
        #expect(alternate.format == "MCBBS"); #expect(alternate.curseForgeFiles.first?.fileID == 10)
        await transfer.discard(alternate)
    }
}
