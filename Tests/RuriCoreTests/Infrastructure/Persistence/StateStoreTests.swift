import Foundation
import Testing
@testable import RuriCore

struct StateStoreTests {
    private func paths() -> LauncherPaths { LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-state-\(UUID())")) }

    @Test func staleWriterWithoutBaselineCannotEraseNewerAccounts() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let baseline = try StateStore.save(PersistentState(), to: paths)
        var other = baseline; other.accounts.append(try Account(username: "OtherPlayer"))
        try StateStore.save(other, to: paths)
        var stale = baseline; stale.settings.defaultMemoryMB = 8192
        #expect(throws: (any Error).self) { try StateStore.save(stale, to: paths) }
        #expect(try StateStore.load(paths).accounts == other.accounts)
        #expect(try StateStore.load(paths).settings.defaultMemoryMB == 4096)
    }
    @Test func concurrentInstallAndPreferencesPreserveBothAndAllowFollowingSave() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var initial = PersistentState(); initial.instances = [GameInstance(name: "Old", gameVersion: "1.21.1")]
        let baseline = try StateStore.save(initial, to: paths)
        let downloaded = GameInstance(name: "Installed elsewhere", gameVersion: "26.2")
        try StateStore.update(paths) { $0.instances.append(downloaded) }
        var local = baseline; local.settings.defaultMemoryMB = 8192; local.instances[0].favorite = true
        var merged = try StateStore.save(local, to: paths, basedOn: baseline)
        #expect(merged.instances.count == 2 && merged.instances.contains(downloaded))
        #expect(merged.instances[0].favorite && merged.settings.defaultMemoryMB == 8192)
        merged.settings.appearance = "dark"
        try StateStore.save(merged, to: paths)
        #expect(try StateStore.load(paths).settings.appearance == "dark")
    }
    @Test func editsToDifferentInstanceFieldsMergeButConflictingRenameAndDeletionFail() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        var initial = PersistentState(); initial.instances = [GameInstance(name: "Original", gameVersion: "1.21.1")]
        let baseline = try StateStore.save(initial, to: paths)
        try StateStore.update(paths) { $0.instances[0].playTime = 600 }
        var local = baseline; local.instances[0].name = "Renamed"
        let merged = try StateStore.save(local, to: paths, basedOn: baseline)
        #expect(merged.instances[0].playTime == 600 && merged.instances[0].name == "Renamed")
        var conflict = baseline; conflict.instances[0].name = "A different name"
        #expect(throws: (any Error).self) { try StateStore.save(conflict, to: paths, basedOn: baseline) }
        var deletion = baseline; deletion.instances.removeAll()
        #expect(throws: (any Error).self) { try StateStore.save(deletion, to: paths, basedOn: baseline) }
        #expect(try StateStore.load(paths).instances == merged.instances)
    }
    @Test func failedMutationAndInvalidReferencesLeaveStateBytesUntouched() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try StateStore.save(PersistentState(), to: paths)
        let data = try Data(contentsOf: paths.state)
        #expect(throws: (any Error).self) {
            try StateStore.update(paths) { state in
                state.settings.defaultMemoryMB = 8192
                throw RuriError.message("cancelled change")
            }
        }
        #expect(throws: (any Error).self) { try StateStore.update(paths) { $0.selectedDirectoryID = UUID() } }
        #expect(try Data(contentsOf: paths.state) == data)
    }
    @Test func aSecondWriterCannotEnterAnActiveTransaction() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try StateStore.update(paths) { state in
            #expect(throws: (any Error).self) { try StateStore.update(paths) { $0.settings.appearance = "dark" } }
            state.settings.defaultMemoryMB = 6144
        }
        #expect(try StateStore.load(paths).settings.defaultMemoryMB == 6144)
        #expect(try StateStore.load(paths).settings.appearance == "system")
    }

    @Test func upgradesEarlierStatesWithoutInventingLocalInstallationsAndRejectsFutureSchemas() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        try paths.prepare()
        var earlier = PersistentState(); earlier.schemaVersion = 9
        earlier.instances = [GameInstance(name: "Existing game", gameVersion: "1.21.1")]
        try JSONEncoder().encode(earlier).write(to: paths.state)
        let loaded = try StateStore.load(paths)
        #expect(loaded.instances.first?.importedInstallation == nil)
        #expect(try StateStore.save(loaded, to: paths).schemaVersion == 11)
        earlier.schemaVersion = 12
        try JSONEncoder().encode(earlier).write(to: paths.state)
        #expect(throws: (any Error).self) { try StateStore.load(paths) }
    }

    @Test func localInstallationMetadataIsValidatedAndMergedAsOneUnit() throws {
        let paths = paths(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let component = MinecraftDirectoryComponent(name: "Fabric", version: "0.16.10")
        var game = GameInstance(name: "Imported game", gameVersion: "1.21.1")
        game.importedInstallation = .init(sourceVersionID: "Original version", components: [component])
        var initial = PersistentState(); initial.instances = [game]
        let baseline = try StateStore.save(initial, to: paths)
        #expect(try StateStore.load(paths).instances == [game])
        #expect(game.subtitle == "Minecraft 1.21.1 · Fabric 0.16.10")
        let bytes = try Data(contentsOf: paths.state)
        let invalid: [ImportedMinecraftInstallation] = [
            .init(sourceVersionID: " ", components: []),
            .init(sourceVersionID: "bad\nlabel", components: []),
            .init(sourceVersionID: "Original", components: [component, component]),
            .init(sourceVersionID: "Original", components: [.init(name: "Bad\ncomponent", version: "1")])
        ]
        for metadata in invalid {
            #expect(throws: (any Error).self) { try StateStore.update(paths) { $0.instances[0].importedInstallation = metadata } }
            #expect(try Data(contentsOf: paths.state) == bytes)
        }
        try StateStore.update(paths) { $0.instances[0].importedInstallation = .init(sourceVersionID: "Other version", components: [component]) }
        var local = baseline
        local.instances[0].importedInstallation = .init(sourceVersionID: "Original version", components: [.init(name: "Fabric", version: "0.19.5")])
        #expect(throws: (any Error).self) { try StateStore.save(local, to: paths, basedOn: baseline) }
        #expect(try StateStore.load(paths).instances[0].importedInstallation?.sourceVersionID == "Other version")
        #expect(try StateStore.load(paths).instances[0].importedInstallation?.components == [component])
    }
}
