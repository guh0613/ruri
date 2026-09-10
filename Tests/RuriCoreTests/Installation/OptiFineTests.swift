import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct OptiFineTests {
    @Test func catalogAndPortablePacksKeepOptiFineIdentity() async throws {
        let fixture = EndpointHTTPFixture(["bmclapi2.bangbang93.com/optifine/1.8.0": Data(#"[{"mcversion":"1.8.0","type":"HD_U_M6","patch":"pre2"},{"mcversion":"1.8.0","type":"HD_U","patch":"M5","forge":"Forge #1902"},{"mcversion":"1.8.0","type":"HD_U_M6","patch":"pre12"},{"mcversion":"1.9","type":"HD_U","patch":"Z1"}]"#.utf8)])
        defer { fixture.close() }
        let releases = try await OptiFineCatalog.releases(game: "1.8", client: HTTPClient(session: fixture.session, routing: NetworkRouting(source: .official)))
        #expect(releases.map(\.version) == ["HD_U_M5", "HD_U_M6_pre12", "HD_U_M6_pre2"])
        #expect(OptiFineCatalog.normalized("1.8.0_HD_U_M5", game: "1.8") == "HD_U_M5")
        #expect(try releases[0].url().absoluteString == "https://bmclapi2.bangbang93.com/optifine/1.8.0/HD_U/M5")
        let helper = HMCLPackTests(), (paths, source) = try helper.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try helper.json(["name": "OptiFine pack", "gameVersion": "1.21.1"], to: "modpack.json", in: source)
        try helper.json(["jar": "1.21.1", "libraries": [["name": "optifine:OptiFine:1.21.1_HD_U_J1"]], "minecraftArguments": "--tweakClass optifine.OptiFineTweaker"], to: "minecraft/pack.json", in: source)
        let transfer = InstanceTransfer(paths: paths), prepared = try await transfer.prepare(source)
        #expect(prepared.instance.loader == .optifine && prepared.instance.loaderVersion == "HD_U_J1")
        let instance = try await transfer.install(prepared, name: "OptiFine pack") { $0 }
        await transfer.discard(prepared)
        for format in [InstanceExportFormat.ruri, .mcbbs] {
            let file = paths.cache.appendingPathComponent(format.rawValue + ".zip")
            try await transfer.export(instance, to: file, format: format)
            let restored = try await transfer.prepare(file)
            #expect(restored.instance.loader == .optifine && restored.instance.loaderVersion == "HD_U_J1")
            await transfer.discard(restored)
        }
        await #expect(throws: (any Error).self) { try await transfer.export(instance, to: paths.cache.appendingPathComponent("pack.mrpack"), format: .mrpack) }
        var installed = instance; installed.installed = true
        installed.repositoryComponents = [.init(name: "OptiFine", version: "HD_U_J1")]
        #expect(InstanceComponents.unavailableReason(installed) == nil)
        installed.repositoryComponents?.append(.init(name: "Forge", version: "52.0.16"))
        #expect(InstanceComponents.unavailableReason(installed)?.contains("多个加载器") == true)
    }

    @Test func patchedArchivesHaveReproducibleHashesWithoutRecompressingEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var outputs: [URL] = []
        let payload = Data(repeating: 0xa5, count: 65536)
        for n in 0..<2 {
            let source = directory.appendingPathComponent("source-\(n).jar"), target = directory.appendingPathComponent("normalized-\(n).jar")
            do {
                let archive = try Archive(url: source, accessMode: .create)
                for (path, data) in [("net/optifine/Fixture.class", payload), ("META-INF/mods.toml", Data("remove this".utf8))] {
                    try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(n * 86400)), compressionMethod: .deflate) { position, count in
                        data.subdata(in: Int(position)..<(Int(position) + count))
                    }
                }
            }
            try OptiFineInstaller.normalize(source, to: target); outputs.append(target)
            let archive = try Archive(url: target, accessMode: .read), entry = try #require(archive["net/optifine/Fixture.class"])
            #expect(archive["META-INF/mods.toml"] == nil)
            var content = Data(); _ = try archive.extract(entry) { content.append($0) }
            #expect(content == payload)
        }
        #expect(try InstanceTransfer.sha1(outputs[0]) == InstanceTransfer.sha1(outputs[1]))
    }
}
