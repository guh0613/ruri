import Foundation
import Testing
@testable import RuriCommandKit
@testable import RuriCore

@MainActor struct ServerCommandTests {
    @Test func favoritesAndDryRunDoNotRequireAnInstanceOrCreateData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let common = ["--data-dir", root.path, "--json"]
        let preview = CommandCapture()
        #expect(await CLIApplication.run(["server", "add", "example.test", "--name", "Favorite", "--dry-run"] + common, write: preview.write) == 0)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let result = CommandCapture()
        #expect(await CLIApplication.run(["server", "add", "example.test", "--name", "Favorite"] + common, write: result.write) == 0)
        let listed = CommandCapture()
        #expect(await CLIApplication.run(["server", "list"] + common, write: listed.write) == 0)
        #expect(try listed.value["data"]["total"] == .integer(1))
        let unset = CommandCapture()
        #expect(await CLIApplication.run(["server", "favorite", "example.test", "--value", "false"] + common, write: unset.write) == 0)
        let unpinned = try #require(try StateStore.load(LauncherPaths(root: root)).servers?.first)
        #expect(!unpinned.favorite && unpinned.saved)
        let forgotten = CommandCapture()
        #expect(await CLIApplication.run(["server", "preferences", "example.test", "--saved", "false", "--alias", ""] + common, write: forgotten.write) == 0)
        #expect(try StateStore.load(LauncherPaths(root: root)).servers?.isEmpty == true)
    }
    @Test func instanceListCRUDAndConflictValidation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: root)
        let instance = try InstanceService(paths: paths).create(name: "Server CLI", game: "1.21.1", selections: [], directoryID: GameDirectory.defaultID)
        let id = instance.id.uuidString, common = ["--data-dir", root.path, "--json"]
        let preview = CommandCapture()
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        #expect(await CLIApplication.run(["server", "add", "localhost", "--instance", id, "--dry-run"] + common, write: preview.write) == 0)
        #expect(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() == before)
        let added = CommandCapture()
        #expect(await CLIApplication.run(["server", "add", "localhost", "--instance", id, "--resource-packs", "never"] + common, write: added.write) == 0)
        let edited = CommandCapture()
        #expect(await CLIApplication.run(["server", "edit", id, "0", "--name", "Renamed"] + common, write: edited.write) == 0)
        #expect(try ServerListManager(paths: paths, instanceID: instance.id).snapshot().entries.first?.name == "Renamed")
        let rejected = CommandCapture()
        #expect(await CLIApplication.run(["server", "remove", id, "0"] + common, write: rejected.write) == 1)
        let conflict = CommandCapture()
        #expect(await CLIApplication.run(["launch", "preflight", id, "--world", "World", "--server", "localhost"] + common, write: conflict.write) == 2)
        #expect(try conflict.value["error"]["code"] == .string("INVALID_ARGUMENT"))
    }
}
