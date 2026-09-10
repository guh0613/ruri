import Foundation
import Testing
import ZIPFoundation
@testable import RuriCore

struct InstanceTransferTests {
    func setup() throws -> (LauncherPaths, GameInstance) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)); try paths.prepare()
        var instance = GameInstance(name: "旅行 \"存档\" 🐱", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.19.5")
        instance.memoryMB = 6144; instance.width = 1600; instance.height = 900; instance.javaPath = "/machine/specific/java"
        instance.extraJVMArguments = "-Dhello=\"two words\" -Dpath=/tmp/example"; instance.installed = true
        for (path, value) in ["saves/World/level.dat": "world-data", "saves/World/session.lock": "lock", "mods/example.jar.disabled": "mod-data", "options.txt": "fov:0.5", "config/test.json": "{}", "config/empty.txt": "", "logs/latest.log": "log", "launcher_accounts.json": "sensitive"] {
            let file = paths.game(instance.id).appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: file)
        }
        return (paths, instance)
    }
    @Test func portableAndMultiMCRoundTrip() async throws {
        let (paths, original) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let transfer = InstanceTransfer(paths: paths)
        for format in [InstanceExportFormat.ruri, .multimc] {
            let zip = paths.cache.appendingPathComponent("\(format.rawValue).zip")
            try await transfer.export(original, to: zip, format: format)
            let archive = try Archive(url: zip, accessMode: .read)
            let prefix = format == .ruri ? "minecraft" : ".minecraft"
            #expect(archive["\(prefix)/launcher_accounts.json"] == nil)
            #expect(archive["\(prefix)/logs/latest.log"] == nil)
            #expect(archive["\(prefix)/saves/World/session.lock"] == nil)
            #expect(archive["\(prefix)/config/empty.txt"]?.uncompressedSize == 0)
            let preview = try await transfer.prepare(zip)
            #expect(preview.instance.name == original.name)
            #expect(preview.instance.loader == .fabric); #expect(preview.instance.loaderVersion == "0.19.5")
            #expect(preview.instance.memoryMB == 6144); #expect(preview.instance.width == 1600)
            #expect(preview.instance.javaPath == nil); #expect(preview.instance.extraJVMArguments == original.extraJVMArguments)
            let installed = try await transfer.install(preview, name: "Imported", importJVMArguments: true) { instance in
                #expect(FileManager.default.fileExists(atPath: paths.game(instance.id).appendingPathComponent("options.txt").path))
                var result = instance; result.installed = true; return result
            }
            #expect(installed.id != original.id); #expect(installed.name == "Imported"); #expect(installed.installed)
            #expect(installed.extraJVMArguments == original.extraJVMArguments)
            #expect(try Data(contentsOf: paths.game(installed.id).appendingPathComponent("saves/World/level.dat")) == Data("world-data".utf8))
            #expect(FileManager.default.fileExists(atPath: paths.game(installed.id).appendingPathComponent("mods/example.jar.disabled").path))
            await transfer.discard(preview)
            #expect(!FileManager.default.fileExists(atPath: preview.workspace.path))
        }
    }
    @Test func failedInstallRollsBackWithoutChangingSource() async throws {
        let (paths, original) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let transfer = InstanceTransfer(paths: paths); let zip = paths.cache.appendingPathComponent("copy.zip")
        try await transfer.export(original, to: zip, includeWorlds: false)
        let prepared = try await transfer.prepare(zip)
        #expect(!FileManager.default.fileExists(atPath: prepared.game.appendingPathComponent("saves").path))
        await #expect(throws: (any Error).self) {
            try await transfer.install(prepared, name: "Failed") { instance in
                #expect(instance.extraJVMArguments.isEmpty)
                throw RuriError.message("Simulated network interruption")
            }
        }
        let dirs = try FileManager.default.contentsOfDirectory(at: paths.instances, includingPropertiesForKeys: nil)
        #expect(dirs.map(\.lastPathComponent) == [original.id.uuidString])
        #expect(try Data(contentsOf: paths.game(original.id).appendingPathComponent("saves/World/level.dat")) == Data("world-data".utf8))
        #expect(FileManager.default.fileExists(atPath: prepared.game.path)) // retry remains possible
        await transfer.discard(prepared)
    }
    @Test func wrappedMultiMCAndUnsupportedPatches() async throws {
        let (paths, original) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let transfer = InstanceTransfer(paths: paths); let zip = paths.cache.appendingPathComponent("prism.zip")
        try await transfer.export(original, to: zip, format: .multimc)
        let outer = paths.cache.appendingPathComponent("wrapper"); let root = outer.appendingPathComponent("My Pack")
        try SafeArchive.extract(zip, to: root)
        let preview = try await transfer.prepare(outer); #expect(preview.instance.name == original.name)
        await transfer.discard(preview)
        let patch = root.appendingPathComponent("patches/custom.json")
        try FileManager.default.createDirectory(at: patch.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: patch)
        await #expect(throws: (any Error).self) { try await transfer.prepare(outer) }
        try FileManager.default.removeItem(at: patch.deletingLastPathComponent())
        let invalid = MultiMCPack(components: [.init(uid: "net.minecraft", version: "1.21.1"), .init(uid: "custom.component", version: "1")])
        try JSONEncoder().encode(invalid).write(to: root.appendingPathComponent("mmc-pack.json"))
        await #expect(throws: (any Error).self) { try await transfer.prepare(root) }
        #expect(try FileManager.default.contentsOfDirectory(at: paths.cache, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("transfer-") }.isEmpty)
    }
    @Test func cancellationPreservesExistingExport() async throws {
        let (paths, original) = try setup(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let destination = paths.cache.appendingPathComponent("old.zip")
        try Data("old export".utf8).write(to: destination)
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await InstanceTransfer(paths: paths).export(original, to: destination)
        }
        await #expect(throws: (any Error).self) { try await operation.value }
        #expect(try Data(contentsOf: destination) == Data("old export".utf8))
    }
}
