import Testing
import Foundation
@testable import RuriCore

struct WorldDataPackTests {
    @Test func editsOnlyPackListsAndPreservesNBTEncoding() throws {
        let helper = WorldTests()
        let opaque = helper.named(5, "float", Data([0x7f, 0xc0, 0x00, 0x01]))
            + helper.named(11, "ints", Data([0, 0, 0, 1, 0x12, 0x34, 0x56, 0x78]))
            + helper.named(9, "emptyLongs", Data([4, 0, 0, 0, 0]))
        let extra = helper.named(1, "custom", Data([1]))
        let original = Data(helper.nbt().dropLast(2)) + opaque + helper.named(10, "DataPacks", extra + Data([0])) + Data([0, 0])
        let updated = try NBTReader.updatingDataPacks(Gzip.compress(original), enabled: ["vanilla", "file/测试🐱.zip"], disabled: ["file/old.zip"])
        #expect(updated.starts(with: [0x1f, 0x8b]))
        let decoded = try Gzip.decompress(updated)
        #expect(decoded.starts(with: Data(helper.nbt().dropLast(2)) + opaque))
        #expect(decoded.range(of: extra) != nil)
        var reader = try NBTReader(data: updated)
        let root = try reader.read()
        #expect(root["Data"]?["LevelName"]?.string == "测试世界🐱")
        #expect(root["Data"]?["DataPacks"]?["Enabled"] == .list([.string("vanilla"), .string("file/测试🐱.zip")]))
        #expect(root["Data"]?["DataPacks"]?["Disabled"] == .list([.string("file/old.zip")]))
        #expect(throws: (any Error).self) { try NBTReader.updatingDataPacks(Data(original.dropLast()), enabled: [], disabled: []) }
    }

    @Test func importsTogglesAndTrashesLocalPacks() async throws {
        let (paths, _, manager, world) = try WorldTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let original = try NBTReader.updatingDataPacks(Data(contentsOf: world.appendingPathComponent("level.dat")), enabled: ["vanilla", "mod:example"], disabled: ["file/old.zip"])
        try original.write(to: world.appendingPathComponent("level.dat"))
        let source = paths.root.appendingPathComponent("测试🐱")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"pack":{"description":{"text":"Example","extra":[{"text":" pack"}]},"min_format":[107,0],"max_format":[107,1]}}"#.utf8).write(to: source.appendingPathComponent("pack.mcmeta"))
        try await manager.importDataPack(from: source, folder: "World")
        var packs = try await manager.dataPacks(folder: "World")
        #expect(packs.count == 1 && packs[0].enabled && packs[0].description == "Example pack")
        #expect(try Data(contentsOf: await manager.dataPackBackup(folder: "World")) == original)
        let imported = packs[0].url
        await #expect(throws: (any Error).self) { try await manager.importDataPack(from: source, folder: "World") }
        try await manager.setDataPackEnabled(false, name: imported.lastPathComponent, folder: "World")
        #expect(try await manager.dataPacks(folder: "World").first?.enabled == false)
        // HMCL disables a folder by renaming its metadata, and a ZIP by suffix.
        try FileManager.default.moveItem(at: imported.appendingPathComponent("pack.mcmeta"), to: imported.appendingPathComponent("pack.mcmeta.disabled"))
        try await manager.setDataPackEnabled(true, name: imported.lastPathComponent, folder: "World")
        #expect(FileManager.default.fileExists(atPath: imported.appendingPathComponent("pack.mcmeta").path))
        let zip = paths.root.appendingPathComponent("archive.zip")
        try SafeArchive.create(from: source, to: zip)
        try await manager.importDataPack(from: zip, folder: "World")
        let installedZIP = world.appendingPathComponent("datapacks/archive.zip")
        try FileManager.default.moveItem(at: installedZIP, to: installedZIP.appendingPathExtension("disabled"))
        try await manager.setDataPackEnabled(true, name: "archive.zip.disabled", folder: "World")
        packs = try await manager.dataPacks(folder: "World")
        #expect(packs.count == 2 && packs.allSatisfy(\.enabled))
        let trash = try await manager.removeDataPack(name: "archive.zip", folder: "World")
        defer { if let trash { try? FileManager.default.removeItem(at: trash) } }
        #expect(!FileManager.default.fileExists(atPath: installedZIP.path))
        #expect(trash.map { FileManager.default.fileExists(atPath: $0.path) } == true)
        var reader = try NBTReader(data: Data(contentsOf: world.appendingPathComponent("level.dat")))
        let selection = try reader.read()["Data"]?["DataPacks"]
        #expect(selection?["Enabled"] == .list([.string("vanilla"), .string("mod:example"), .string("file/测试🐱")]))
        #expect(selection?["Disabled"] == .list([.string("file/old.zip")]))
        #expect(try Data(contentsOf: world.appendingPathComponent("region/r.0.0.mca")) == Data("generation-a".utf8))
    }
}
