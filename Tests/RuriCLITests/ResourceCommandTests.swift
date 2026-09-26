import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

@MainActor struct ResourceCommandTests {
    private func fixture() throws -> (LauncherPaths, GameInstance) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let instance = try InstanceService(paths: paths).create(name: "Resources", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        return (paths, instance)
    }
    private func invoke(_ args: [String], _ paths: LauncherPaths) async throws -> (Int32, Value) {
        let output = CommandCapture(), status = await CLIApplication.run(args + ["--data-dir", paths.root.path, "--json"], write: output.write)
        return (status, try output.value)
    }
    @Test func contentCanBeImportedDisabledAndReenabledWithoutNetwork() async throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let source = paths.root.appendingPathComponent("Sample pack")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data(#"{"pack":{"pack_format":34,"description":"Fixture"}}"#.utf8).write(to: source.appendingPathComponent("pack.mcmeta"))
        let arguments = ["content", "import", instance.id.uuidString, source.path, "--kind", "resourcepack"]
        #expect(try await invoke(arguments + ["--dry-run"], paths).0 == 0)
        let destination = paths.game(instance.id).appendingPathComponent("resourcepacks/Sample pack")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(try await invoke(arguments, paths).0 == 0)
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(try await invoke(["content", "disable", instance.id.uuidString, "--file", "Sample pack", "--kind", "resourcepack"], paths).0 == 0)
        let entries = try await ContentManager(paths: paths.configured(with: StateStore.load(paths)), instanceID: instance.id).scan(.resourcepack)
        #expect(entries.count == 1 && entries[0].enabled == false)
        #expect(try await invoke(["content", "enable", instance.id.uuidString, "--file", entries[0].url.lastPathComponent, "--kind", "resourcepack"], paths).0 == 0)
        #expect(try await invoke(["content", "remove", instance.id.uuidString, "--all", "--kind", "resourcepack"], paths).0 == 1)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }
    @Test func readAndPreviewNeverRecoverPendingContentImplicitly() async throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let pending = paths.instance(instance.id).appendingPathComponent("content-transaction")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        try Data("marker".utf8).write(to: pending.appendingPathComponent("committed"))
        let result = try await invoke(["content", "list", instance.id.uuidString], paths)
        #expect(result.0 == 1)
        #expect(result.1["error"]["code"] == .string("RECOVERY_REQUIRED"))
        #expect(FileManager.default.fileExists(atPath: pending.path))
        #expect(try await invoke(["recovery", "apply", "content", instance.id.uuidString, "--yes"], paths).0 == 0)
        #expect(!FileManager.default.fileExists(atPath: pending.path))
    }
    @Test func worldBackupRestoreAndDataPackPriorityRoundTrip() async throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        func string(_ s: String) -> Data { let data = Data(s.utf8); return Data([UInt8(data.count >> 8), UInt8(data.count & 255)]) + data }
        func named(_ type: UInt8, _ name: String, _ data: Data) -> Data { Data([type]) + string(name) + data }
        let nbt = Data([10,0,0]) + named(10, "Data", named(8, "LevelName", string("Fixture")) + Data([0])) + Data([0])
        let world = paths.game(instance.id).appendingPathComponent("saves/World")
        try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
        try nbt.write(to: world.appendingPathComponent("level.dat"))
        let created = try await invoke(["world", "backup", "create", instance.id.uuidString, "World"], paths)
        #expect(created.0 == 0)
        let backup = try #require(created.1["data"]["id"].string)
        #expect(try await invoke(["world", "backup", "restore", instance.id.uuidString, backup, "--yes"], paths).0 == 0)
        let worlds = try await WorldManager(paths: paths, instanceID: instance.id).worlds()
        #expect(worlds.count == 2)
        let source = paths.root.appendingPathComponent("Example.zip"), data = paths.root.appendingPathComponent("pack.mcmeta")
        try Data(#"{"pack":{"pack_format":48,"description":"Test data pack"}}"#.utf8).write(to: data)
        #expect(try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/zip"), arguments: ["-q", source.path, "pack.mcmeta"], directory: paths.root).0 == 0)
        #expect(try await invoke(["datapack", "import", instance.id.uuidString, "World", source.path], paths).0 == 0)
        let listed = try await invoke(["datapack", "order", "get", instance.id.uuidString, "World"], paths)
        #expect(listed.0 == 0)
        let beforePreview = try Data(contentsOf: world.appendingPathComponent("level.dat"))
        #expect(try await invoke(["world", "remove", instance.id.uuidString, "World", "--dry-run"], paths).0 == 0)
        #expect(try Data(contentsOf: world.appendingPathComponent("level.dat")) == beforePreview)
    }
    @Test func allCommandDescriptorsHaveUniquePathsAndGuardDestructiveActions() throws {
        let paths = CommandRegistry.commands.map { $0.path.joined(separator: " ") }
        #expect(Set(paths).count == paths.count)
        for spec in CommandRegistry.commands where spec.confirmation {
            #expect(spec.mutation)
            #expect(spec.supportsDryRun)
            #expect(spec.options.contains { $0.name == "yes" && $0.type == "bool" })
        }
    }
    @Test func completeInstanceArchiveRoundTripUsesNoNetwork() async throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try StateStore.update(paths) { $0.instances[0].installed = true }
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        try Data(#"{"id":"1.21.1","mainClass":"Main","libraries":[],"minecraftArguments":"--username ${auth_player_name}","javaVersion":{"majorVersion":21}}"#.utf8).write(to: paths.manifest(instance.id))
        let jar = paths.versions.appendingPathComponent("1.21.1/1.21.1.jar")
        try FileManager.default.createDirectory(at: jar.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: jar)
        let archive = paths.root.deletingLastPathComponent().appendingPathComponent("complete-\(UUID()).zip")
        defer { try? FileManager.default.removeItem(at: archive) }
        let exported = try await invoke(["instance", "export", instance.id.uuidString, archive.path, "--format", "complete"], paths)
        try #require(exported.0 == 0, "\(exported.1)")
        let preview = try await invoke(["instance", "import", archive.path, "--name", "Imported", "--directory", "default", "--dry-run"], paths)
        try #require(preview.0 == 0, "\(preview.1)")
        #expect(try StateStore.load(paths).instances.count == 1)
        let imported = try await invoke(["instance", "import", archive.path, "--name", "Imported", "--directory", "default"], paths)
        #expect(imported.0 == 0, "\(imported.1)")
        #expect(try StateStore.load(paths).instances.count == 2)
    }
}
