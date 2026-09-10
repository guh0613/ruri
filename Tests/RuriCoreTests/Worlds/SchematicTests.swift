import Foundation
import Testing
@testable import RuriCore

struct SchematicTests {
    @Test func managesFoldersAndPreservesSchematicFilesAndMetadata() async throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        let id = UUID(), helper = WorldTests(), manager = SchematicManager(paths: paths, instanceID: id)
        func integer(_ value: UInt32) -> Data { Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]) }
        let preview = Data([255, 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255])
        let dimensions = ["x", "y", "z"].enumerated().reduce(Data()) { $0 + helper.named(3, $1.element, integer(UInt32($1.offset + 1))) } + Data([0])
        let metadata = helper.named(8, "Name", helper.string("我的小屋")) + helper.named(8, "Author", helper.string("Builder"))
            + helper.named(3, "TotalBlocks", integer(6)) + helper.named(10, "EnclosingSize", dimensions)
            + helper.named(11, "PreviewImageData", integer(4) + preview) + Data([0])
        let litematic = Data([10, 0, 0]) + helper.named(3, "Version", integer(6)) + helper.named(10, "Metadata", metadata) + helper.named(10, "Regions", Data([0])) + Data([0])
        let source = paths.cache.appendingPathComponent("house.litematic"), bytes = try Gzip.compress(litematic)
        try bytes.write(to: source)
        try await manager.createFolder("Buildings")
        try await manager.importFiles([source], directory: "Buildings")
        let entry = try #require(await manager.list(directory: "Buildings").first)
        let info = try await manager.info(entry)
        #expect(info.name == "我的小屋" && info.author == "Builder" && info.blocks == 6)
        #expect(info.dimensions == [1, 2, 3] && info.previewARGB == preview && info.formatVersion == 6)
        let exported = paths.cache.appendingPathComponent("exported.litematic")
        try Data("old export".utf8).write(to: exported)
        try await manager.export(entry, to: exported)
        #expect(try Data(contentsOf: exported) == bytes)
        let another = paths.cache.appendingPathComponent("other.litematic"); try bytes.write(to: another)
        await #expect(throws: (any Error).self) { try await manager.importFiles([another, source], directory: "Buildings") }
        #expect(try await manager.list(directory: "Buildings").count == 1)
        try FileManager.default.createSymbolicLink(at: paths.game(id).appendingPathComponent("schematics/alias"), withDestinationURL: paths.cache)
        await #expect(throws: (any Error).self) { try await manager.importFiles([another], directory: "alias") }
        let trash = try await manager.remove(entry)
        defer { if let trash { try? FileManager.default.removeItem(at: trash) } }
        #expect(try await manager.list(directory: "Buildings").isEmpty)
        #expect(try Data(contentsOf: source) == bytes)
        // Sponge v3 nests the data and stores dimensions as unsigned shorts.
        let sponge = helper.named(3, "Version", integer(3)) + helper.named(2, "Width", Data([0xff, 0xff]))
            + helper.named(2, "Height", Data([0, 2])) + helper.named(2, "Length", Data([0, 3])) + Data([0])
        let schematic = paths.cache.appendingPathComponent("area.schem")
        try (Data([10, 0, 0]) + helper.named(10, "Schematic", sponge) + Data([0])).write(to: schematic)
        try await manager.importFiles([schematic])
        let schematicEntry = try #require(await manager.list().first { !$0.isDirectory })
        #expect(try await manager.info(schematicEntry).dimensions == [65535, 2, 3])
    }
}
