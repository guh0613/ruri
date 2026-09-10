import Foundation
import Testing
@testable import RuriCore

struct ModpackRegistryTests {
    @Test func baselineRetainsOriginAndPreservesUserChangesAcrossPortableTransfer() async throws {
        let fixture = MRPackTests(); let (paths, source) = try fixture.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try fixture.index([fixture.file("mods/required.jar"), fixture.file("mods/optional.jar", client: "optional")], at: source)
        try fixture.write(Data("initial config".utf8), "overrides/config/test.json", in: source)
        let origin = ModpackOrigin(provider: .modrinth, projectID: "project", versionID: "version")
        let transfer = InstanceTransfer(paths: paths)
        let prepared = try await transfer.prepare(source, origin: origin).selectingOptionalFiles(excluding: ["mods/optional.jar"])
        try await transfer.completeFiles(prepared, downloader: DownloadManager(configuration: fixture.config(), retryDelay: .zero)) { _ in }
        let instance = try await transfer.install(prepared, name: "Personal name") { instance in
            try fixture.write(Data("generated runtime cache".utf8), ".fabric/remapped.jar", in: paths.game(instance.id))
            var result = instance; result.installed = true; return result
        }
        let baseline = try #require(try ModpackRegistry.load(paths: paths, instanceID: instance.id))
        #expect(baseline.origin == origin); #expect(baseline.version == "v2")
        #expect(baseline.settings.name == "Test Pack"); #expect(instance.name == "Personal name")
        #expect(baseline.files.count == 2); #expect(baseline.files.allSatisfy { !$0.path.contains("optional") && !$0.path.contains(".fabric") })
        #expect(baseline.files.first(where: { $0.path == "mods/required.jar" })?.identities == ["modrinth:project"])
        let oldHash = try #require(baseline.files.first(where: { $0.path == "config/test.json" })?.sha1)
        try fixture.write(Data("user-edited config".utf8), "config/test.json", in: paths.game(instance.id))
        let zip = paths.cache.appendingPathComponent("portable.zip")
        try await transfer.export(instance, to: zip)
        let migrated = try await transfer.prepare(zip)
        let copy = try await transfer.install(migrated, name: "Moved") { $0 }
        let copiedBaseline = try #require(try ModpackRegistry.load(paths: paths, instanceID: copy.id))
        #expect(copiedBaseline.files.first(where: { $0.path == "config/test.json" })?.sha1 == oldHash)
        #expect(try InstanceTransfer.sha1(paths.game(copy.id).appendingPathComponent("config/test.json")) != oldHash)
        #expect(copiedBaseline.settings.id == copy.id)
        await transfer.discard(prepared); await transfer.discard(migrated)
    }
    @Test func mcbbsBaselineRetainsFileUpdateRules() async throws {
        let fixture = HMCLPackTests(); let (paths, source) = try fixture.setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let data = Data("config".utf8)
        try fixture.json(["manifestType": "minecraftModpack", "manifestVersion": 2, "name": "MCBBS", "version": "2", "fileApi": "https://updates.example.test/pack",
                          "addons": [["id": "game", "version": "1.21.1"]], "files": [["type": "addon", "path": "config/test.json", "hash": fixture.hash(data), "force": true]]], to: "mcbbs.packmeta", in: source)
        try fixture.write(data, to: "overrides/config/test.json", in: source)
        let transfer = InstanceTransfer(paths: paths); let prepared = try await transfer.prepare(source)
        let instance = try await transfer.install(prepared, name: "MCBBS") { $0 }
        let record = try #require(try ModpackRegistry.load(paths: paths, instanceID: instance.id))
        #expect(record.files.first?.force == true); #expect(record.origin?.fileAPI?.absoluteString == "https://updates.example.test/pack")
        await transfer.discard(prepared)
    }
    @Test func invalidMigratedBaselineCannotReferenceOutsideGameDirectory() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let instance = GameInstance(name: "Invalid", gameVersion: "1.21.1")
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let record = InstalledModpack(format: "Modrinth", name: "Invalid", version: "1", origin: nil, settings: instance,
                                      files: [.init(path: "../../other", sha1: String(repeating: "0", count: 40), size: 0, force: false, identities: [])])
        try JSONEncoder().encode(record).write(to: paths.instance(instance.id).appendingPathComponent("modpack-state.json"))
        #expect(throws: (any Error).self) { try ModpackRegistry.load(paths: paths, instanceID: instance.id) }
    }
}
