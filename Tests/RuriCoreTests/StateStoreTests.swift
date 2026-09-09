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
}
