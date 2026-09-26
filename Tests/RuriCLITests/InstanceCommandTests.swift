import Foundation
import Testing
@testable import RuriCommandKit
import RuriCore

struct InstanceCommandTests {
    @MainActor @Test func explicitCreationAndMetadataRoundTrip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let common = ["--data-dir", root.path, "--json"]
        let preview = CommandCapture()
        #expect(await CLIApplication.run(["instance", "create", "--name", "CLI Test", "--game", "1.21.1", "--directory", "default", "--no-install", "--dry-run"] + common, write: preview.write) == 0)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let created = CommandCapture()
        #expect(await CLIApplication.run(["instance", "create", "--name", "CLI Test", "--game", "1.21.1", "--directory", "default", "--no-install"] + common, write: created.write) == 0)
        let id = try #require(created.value["data"]["instance"]["id"].string)
        let renamed = CommandCapture()
        #expect(await CLIApplication.run(["instance", "rename", id, "Renamed"] + common, write: renamed.write) == 0)
        let shown = CommandCapture()
        #expect(await CLIApplication.run(["instance", "show", "--name", "Renamed"] + common, write: shown.write) == 0)
        #expect(try shown.value["data"]["id"] == .string(id))
        let rejected = CommandCapture()
        #expect(await CLIApplication.run(["instance", "remove", id] + common, write: rejected.write) == 1)
        #expect(try rejected.value["error"]["code"] == .string("CONFIRMATION_REQUIRED"))
        #expect(try StateStore.load(LauncherPaths(root: root)).instances.count == 1)
    }
    @Test func exactNamesNeverResolveAmbiguously() throws {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = InstanceService(paths: paths)
        _ = try service.create(name: "Same", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        _ = try service.create(name: "Same", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        do { _ = try service.resolve(name: "Same"); Issue.record("Expected an ambiguous target") }
        catch let failure as OperationFailure { #expect(failure.code == "AMBIGUOUS_TARGET") }
    }
    @Test func customRunDirectoryInspectionDoesNotRegisterIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root.appendingPathComponent("data")), target = root.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let instance = try InstanceService(paths: paths).create(name: "Test", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        let original = try Data(contentsOf: paths.state)
        let preview = try await GameRunDirectoryChange(paths: paths).inspect(instanceID: instance.id, target: .custom, customPath: target)
        #expect(preview.target == target.resolvingSymlinksInPath())
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        #expect(try Data(contentsOf: paths.state) == original)
    }
}
