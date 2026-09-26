import Foundation
import Testing
@testable import RuriCore

struct ConfigurationEditingTests {
    private func fixture() throws -> (LauncherPaths, GameInstance) {
        let paths = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var instance = GameInstance(name: "Original", gameVersion: "1.21.1")
        instance.launchOverrides = .init(fixing: LaunchSettingsValues())
        try StateStore.update(paths) { $0.instances = [instance] }
        return (paths, instance)
    }
    @Test func guiDefaultsPreserveDifferentCLIFieldsAndRejectSameField() throws {
        let (paths, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths), original = try StateStore.load(paths).settings.defaultLaunchSettings
        var draft = original; draft.window.width = 1440
        _ = try service.apply(.init(set: ["window.height": .integer(900)]), scope: "defaults")
        let merged = try service.saveDefaults(draft, basedOn: original)
        #expect(merged.settings.defaultLaunchSettings.window == GameWindowSize(width: 1440, height: 900))
        draft.window.width = 1920
        let bytes = try Data(contentsOf: paths.state)
        do { _ = try service.saveDefaults(draft, basedOn: original); Issue.record("Expected conflict") }
        catch let failure as OperationFailure { #expect(failure.code == "STATE_CONFLICT") }
        #expect(try Data(contentsOf: paths.state) == bytes)
    }
    @Test func instanceDraftMergesSubfieldsWithoutLosingPlaytimeOrOtherGroups() throws {
        let (paths, original) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths)
        var draft = original; draft.name = "Edited"; draft.launchOverrides!.window!.width = 1440
        _ = try service.apply(.init(set: ["window.height": .integer(1000), "presentation.showLogs": .bool(true)]), scope: "instance:\(original.id)")
        try StateStore.update(paths) { $0.instances[0].playTime = 300 }
        let current = try service.saveInstanceSettings(draft, basedOn: original).instances[0]
        #expect(current.name == "Edited" && current.playTime == 300)
        #expect(current.effectiveLaunchOverrides.window == GameWindowSize(width: 1440, height: 1000))
        #expect(current.effectiveLaunchOverrides.presentation?.showLogs == true)
        let bytes = try Data(contentsOf: paths.state)
        #expect(try service.saveInstanceSettings(draft, basedOn: original).instances[0] == current)
        #expect(try Data(contentsOf: paths.state) == bytes)
    }
    @Test func inheritanceConflictDoesNotCommitMetadata() throws {
        let (paths, original) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = ConfigurationService(paths: paths)
        var draft = original; draft.name = "Uncommitted"; draft.launchOverrides!.window!.width = 1440
        _ = try service.apply(.init(inherit: ["window"]), scope: "instance:\(original.id)")
        let bytes = try Data(contentsOf: paths.state)
        #expect(throws: OperationFailure.self) { try service.saveInstanceSettings(draft, basedOn: original) }
        #expect(try Data(contentsOf: paths.state) == bytes)
        #expect(try StateStore.load(paths).instances[0].name == "Original")
    }
    @Test func deletedInstanceIsNeverResurrectedByAnEditor() throws {
        let (paths, original) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try StateStore.update(paths) { $0.instances.removeAll() }
        var draft = original; draft.favorite = true
        #expect(throws: OperationFailure.self) { try ConfigurationService(paths: paths).saveInstanceSettings(draft, basedOn: original) }
        #expect(try StateStore.load(paths).instances.isEmpty)
    }
}
