import Testing
import Foundation
import ZIPFoundation
@testable import RuriCore

struct WorldTests {
    func string(_ value: String) -> Data { let bytes = Data(value.utf8); return Data([UInt8(bytes.count >> 8), UInt8(bytes.count & 255)]) + bytes }
    func named(_ type: UInt8, _ name: String, _ payload: Data) -> Data { Data([type]) + string(name) + payload }
    func nbt() -> Data {
        let version = named(8, "Name", string("1.21.1")) + Data([0])
        let world = named(8, "LevelName", string("测试世界🐱")) + named(3, "GameType", Data([0,0,0,1])) + named(10, "Version", version) + Data([0])
        return Data([10,0,0]) + named(10, "Data", world) + Data([0])
    }
    func setup() throws -> (LauncherPaths, UUID, WorldManager, URL) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        let id = UUID(); let world = paths.game(id).appendingPathComponent("saves/World")
        try FileManager.default.createDirectory(at: world.appendingPathComponent("region"), withIntermediateDirectories: true)
        try nbt().write(to: world.appendingPathComponent("level.dat"))
        try Data("generation-a".utf8).write(to: world.appendingPathComponent("region/r.0.0.mca"))
        try Data("lock".utf8).write(to: world.appendingPathComponent("session.lock"))
        return (paths, id, WorldManager(paths: paths, instanceID: id), world)
    }
    @Test func readsNBTAndRejectsTruncation() throws {
        var reader = try NBTReader(data: nbt()); let root = try reader.read()
        #expect(root["Data"]?["LevelName"]?.string == "测试世界🐱")
        #expect(root["Data"]?["GameType"]?.integer == 1)
        var broken = try NBTReader(data: nbt().dropLast(2))
        #expect(throws: (any Error).self) { try broken.read() }
        let surrogateString = Data([10,0,0,8,0,1,110,0,6,0xed,0xa0,0xbd,0xed,0xb8,0xb1,0])
        var modified = try NBTReader(data: surrogateString)
        #expect(try modified.read()["n"]?.string == "😱")
    }
    @Test func gzipValidatesChecksumAndOutputLimit() throws {
        let compressed = Data(base64Encoded: "H4sIAAAAAAACA8tIzcnJVyjPL8pJAQCFEUoNCwAAAA==")!
        #expect(try Gzip.decompress(compressed) == Data("hello world".utf8))
        #expect(throws: (any Error).self) { try Gzip.decompress(compressed, limit: 4) }
        var corrupt = compressed; corrupt[corrupt.count - 8] ^= 1
        #expect(throws: (any Error).self) { try Gzip.decompress(corrupt) }
    }
    @Test func backupRestoreAndImportPreserveWorldData() async throws {
        let (paths, id, manager, world) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let listed = try #require(await manager.worlds().first)
        #expect(listed.name == "测试世界🐱"); #expect(listed.version == "1.21.1"); #expect(listed.gameMode == "创造")
        let backup = try await manager.backup(folder: "World")
        let archive = try Archive(url: backup.url, accessMode: .read)
        #expect(archive["world/session.lock"] == nil)
        #expect(archive["world/region/r.0.0.mca"] != nil)
        try Data("generation-b".utf8).write(to: world.appendingPathComponent("region/r.0.0.mca"))
        let restored = try await manager.restore(backup)
        #expect(restored != "World")
        #expect(try Data(contentsOf: world.appendingPathComponent("region/r.0.0.mca")) == Data("generation-b".utf8))
        #expect(try Data(contentsOf: paths.game(id).appendingPathComponent("saves/\(restored)/region/r.0.0.mca")) == Data("generation-a".utf8))
        _ = try await manager.restore(backup, replaceExisting: true)
        #expect(try Data(contentsOf: world.appendingPathComponent("region/r.0.0.mca")) == Data("generation-a".utf8))
        let backups = try await manager.backups()
        #expect(backups.count == 2)
        #expect(backups.contains { $0.metadata?.reason == "恢复前自动备份" })
        let imported = try await manager.importWorld(from: backup.url)
        #expect(FileManager.default.fileExists(atPath: paths.game(id).appendingPathComponent("saves/\(imported)/level.dat").path))
    }
    @Test func corruptArchiveNeverReplacesCurrentWorld() async throws {
        let (paths, _, manager, world) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let backup = try await manager.backup(folder: "World")
        try Data("not a zip".utf8).write(to: backup.url)
        await #expect(throws: (any Error).self) { try await manager.restore(backup, replaceExisting: true) }
        #expect(try Data(contentsOf: world.appendingPathComponent("region/r.0.0.mca")) == Data("generation-a".utf8))
    }
    @Test func recoversInterruptionBetweenDirectoryRenames() async throws {
        let (paths, id, manager, world) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let tx = paths.instance(id).appendingPathComponent("world-restore")
        try FileManager.default.createDirectory(at: tx.appendingPathComponent("incoming"), withIntermediateDirectories: true)
        try JSONEncoder().encode(WorldManager.RestoreJournal(folder: "World", hadOriginal: true)).write(to: tx.appendingPathComponent("journal.json"))
        try FileManager.default.moveItem(at: world, to: tx.appendingPathComponent("previous"))
        try await manager.recover()
        #expect(try Data(contentsOf: world.appendingPathComponent("region/r.0.0.mca")) == Data("generation-a".utf8))
        #expect(!FileManager.default.fileExists(atPath: tx.path))
    }
    @Test func archiveRejectsSourceMutationAndSymlinks() throws {
        let (paths, _, _, world) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let target = paths.cache.appendingPathComponent("backup.zip")
        #expect(throws: (any Error).self) {
            try SafeArchive.create(from: world, to: target) { completed, _ in
                if completed == 1 { try? Data("changed during backup".utf8).write(to: world.appendingPathComponent("level.dat")) }
            }
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        try FileManager.default.createSymbolicLink(at: world.appendingPathComponent("outside"), withDestinationURL: paths.root)
        #expect(throws: (any Error).self) { try SafeArchive.create(from: world, to: target) }
    }
}
