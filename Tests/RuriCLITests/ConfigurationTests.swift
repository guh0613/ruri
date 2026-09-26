import Foundation
import Testing
import RuriCore
@testable import RuriCommandKit

struct ConfigurationTests {
    private func fixture() throws -> (LauncherPaths, GameInstance) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var instance = GameInstance(name: "Test", gameVersion: "1.21.1"); instance.launchOverrides = .init()
        try StateStore.update(paths) { $0.instances = [instance] }
        return (paths, instance)
    }
    @Test func patchIsAtomicAndPreservesInheritanceGroups() throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths), scope = "instance:\(instance.id)"
        let original = try Data(contentsOf: paths.state)
        #expect(throws: OperationFailure.self) { try service.apply(.init(set: ["window.width": .integer(1440), "unknown": .bool(true)]), scope: scope) }
        #expect(try Data(contentsOf: paths.state) == original)
        let preview = try service.apply(.init(set: ["window.width": .integer(1440)]), scope: scope, dryRun: true)
        #expect(preview["after"]["effective"]["window"]["width"] == .integer(1440))
        #expect(try Data(contentsOf: paths.state) == original)
        _ = try service.apply(.init(set: ["window.width": .integer(1440)]), scope: scope)
        let state = try StateStore.load(paths)
        #expect(state.instances[0].effectiveLaunchOverrides.window?.height == 800)
        #expect(state.instances[0].effectiveLaunchOverrides.memory == nil)
        let report = try service.read(scope: scope)
        #expect(report["sources"]["window"] == .string("instance"))
        _ = try service.apply(.init(inherit: ["window"]), scope: scope)
        #expect(try service.read(scope: scope)["sources"]["window"] == .string("defaults"))
    }
    @Test func noOpAndRevisionConflict() throws {
        let (paths, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths), original = try Data(contentsOf: paths.state)
        #expect(try service.apply(.init(set: ["window.width": .integer(1280)]), scope: "defaults")["changed"] == .bool(false))
        #expect(try Data(contentsOf: paths.state) == original)
        let revision = try StateStore.load(paths).revision!
        _ = try service.apply(.init(set: ["window.width": .integer(1440)]), scope: "defaults")
        #expect(throws: OperationFailure.self) { try service.apply(.init(set: ["appearance": .string("dark")]), scope: "app", expectedRevision: revision) }
        #expect(try StateStore.load(paths).settings.appearance == "system")
    }
    @Test func environmentIsRedactedAndEmptyIsAnOverride() throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths), scope = "instance:\(instance.id)"
        _ = try service.apply(.init(set: ["environment": .string("API_TOKEN=secret-value")]), scope: "defaults")
        #expect(try service.read(scope: scope)["effective"]["environment"]["names"] == .array([.string("API_TOKEN")]))
        #expect(try service.read(scope: scope, showSecrets: true)["effective"]["environment"] == .string("API_TOKEN=secret-value"))
        _ = try service.apply(.init(set: ["environment": .string("")]), scope: scope)
        #expect(try StateStore.load(paths).instances[0].effectiveLaunchOverrides.environment == "")
        _ = try service.apply(.init(inherit: ["environment"]), scope: scope)
        #expect(try StateStore.load(paths).instances[0].effectiveLaunchOverrides.environment == nil)
    }
    @Test func invalidGroupCombinationDoesNotWrite() throws {
        let (paths, instance) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths), original = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) { try service.apply(.init(set: ["memory.mode": .string("manual"), "memory.maximumMB": .integer(1024), "memory.initialMB": .integer(4096)]), scope: "defaults") }
        #expect(throws: OperationFailure.self) { try service.apply(.init(set: ["window.width": .integer(1440)], inherit: ["window"]), scope: "instance:\(instance.id)") }
        #expect(try Data(contentsOf: paths.state) == original)
    }
    @MainActor @Test func commandRoundTripAndUnknownPatchKey() async throws {
        let (paths, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let output = CommandCapture()
        #expect(await CLIApplication.run(["config", "set", "appearance", "\"dark\"", "--scope", "app", "--data-dir", paths.root.path, "--json"], write: output.write) == 0)
        #expect(try output.value["data"]["after"]["effective"]["appearance"] == .string("dark"))
        #expect(throws: OperationFailure.self) { try JSONDecoder().decode(ConfigurationPatch.self, from: Data("{\"typo\":{}}".utf8)) }
    }
}
