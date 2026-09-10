import Foundation
import Testing
@testable import RuriCore

struct GameDirectoryTests {
    private func fixture() throws -> (URL, LauncherPaths, GameDirectory) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-directories-\(UUID())")
        let external = root.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let paths = LauncherPaths(root: root.appendingPathComponent("app"))
        let directory = try GameDirectory.create(name: "整合包", at: external, paths: paths)
        return (root, paths, directory)
    }

    @Test func oldInstancesStayPutWhileNewInstancesUseSelectedDirectoryAndStateRoundTrips() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = GameInstance(name: "旧实例", gameVersion: "1.21.1")
        var state = PersistentState(); state.instances = [old]; state.gameDirectories = [directory]; state.selectedDirectoryID = directory.id
        let paths = base.configured(with: state)
        #expect(paths.instance(old.id) == base.instance(old.id))
        #expect(paths.game(old.id) == base.game(old.id))
        let newID = UUID()
        #expect(paths.instance(newID) == directory.url.appendingPathComponent("instances/\(newID)"))
        #expect(paths.assets == base.assets && paths.libraries == base.libraries && paths.runtimes == base.runtimes)
        try StateStore.save(state, to: base)
        let loaded = try StateStore.load(base)
        #expect(loaded.schemaVersion == 11 && loaded.gameDirectories == [directory])
        #expect(base.configured(with: loaded).instance(old.id) == base.instance(old.id))
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        legacy.removeValue(forKey: "directoryID")
        #expect(try JSONDecoder().decode(GameInstance.self, from: JSONSerialization.data(withJSONObject: legacy)).directoryID == nil)
    }

    @Test func missingOrReplacedExternalFolderCannotBeRecreatedByMutation() async throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let instance = GameInstance(name: "External", gameVersion: "1.21.1")
        let paths = LauncherPaths(root: base.root, directories: [directory], instanceDirectories: [instance.id: directory.id])
        try paths.prepareInstance(instance.id)
        try FileManager.default.removeItem(at: directory.url)
        #expect(throws: (any Error).self) { try paths.prepareInstance(instance.id) }
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: instance.id) }
        await #expect(throws: (any Error).self) { try await ContentManager(paths: paths, instanceID: instance.id).recover() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths, instanceID: instance.id).recover() }
        #expect(!FileManager.default.fileExists(atPath: directory.url.path))
        try FileManager.default.createDirectory(at: directory.url, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try paths.prepareInstance(instance.id) }
        #expect(!FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("instances").path))
    }

    @Test func registrationRejectsNestedDuplicateAndOccupiedFoldersAndInvalidReferences() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: base.root, directories: [directory])
        #expect(throws: (any Error).self) { try GameDirectory.create(name: "重复", at: directory.url, paths: paths) }
        let nested = directory.url.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try GameDirectory.create(name: "嵌套", at: nested, paths: paths) }
        let occupied = root.appendingPathComponent("existing-minecraft")
        try FileManager.default.createDirectory(at: occupied.appendingPathComponent("versions"), withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try GameDirectory.create(name: "Existing", at: occupied, paths: paths) }
        #expect(!FileManager.default.fileExists(atPath: occupied.appendingPathComponent(GameDirectory.markerName).path))
        let broken = LauncherPaths(root: base.root, instanceDirectories: [UUID(): UUID()])
        #expect(throws: (any Error).self) { try broken.validateDirectoryConfiguration() }
    }

    @Test func relocationRequiresOriginalMarkerAndPreservesInstanceContents() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let paths = LauncherPaths(root: base.root, directories: [directory], newInstanceDirectoryID: directory.id)
        let id = UUID(); try paths.prepareInstance(id)
        try Data("preserved".utf8).write(to: paths.instance(id).appendingPathComponent("proof.txt"))
        let moved = root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: directory.url, to: moved)
        let result = try directory.relocated(to: moved, paths: paths)
        #expect(result.id == directory.id)
        #expect(try String(contentsOf: moved.appendingPathComponent("instances/\(id)/proof.txt"), encoding: .utf8) == "preserved")
        let unrelated = root.appendingPathComponent("unrelated")
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try directory.relocated(to: unrelated, paths: paths) }
    }

    @Test func internalSymlinkEscapeIsRejectedBeforeWriting() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: directory.url.appendingPathComponent("instances"), withDestinationURL: outside)
        let paths = LauncherPaths(root: base.root, directories: [directory], newInstanceDirectoryID: directory.id)
        #expect(throws: (any Error).self) { try paths.prepareInstance(UUID()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    @Test func directoryTransactionsCanRenameRemoveAndReattachAnEmptyFolder() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var state = PersistentState(); state.gameDirectories = [directory]; state.selectedDirectoryID = directory.id
        try StateStore.save(state, to: base)
        try GameDirectoryStore.rename(directory.id, name: "New name", paths: base)
        #expect(try StateStore.load(base).gameDirectories?.first?.name == "New name")
        try GameDirectoryStore.remove(directory.id, paths: base)
        #expect(try StateStore.load(base).selectedDirectoryID == nil)
        #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent(GameDirectory.markerName).path))
        let attached = try GameDirectoryStore.add(name: "Reattached", url: directory.url, paths: base)
        #expect(attached.gameDirectories?.first?.id == directory.id && attached.selectedDirectoryID == directory.id)
        let pending = directory.url.appendingPathComponent("instances/\(UUID())")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try GameDirectoryStore.remove(directory.id, paths: base) }
        try FileManager.default.removeItem(at: pending)
        var instance = GameInstance(name: "Present", gameVersion: "1.21.1"); instance.directoryID = directory.id
        try StateStore.update(base) { $0.instances.append(instance) }
        #expect(throws: (any Error).self) { try GameDirectoryStore.remove(directory.id, paths: base) }
        #expect(try StateStore.load(base).instances == [instance])
    }

    @Test func relocationRejectsAnOpenLeaseAtTheMovedLocation() throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var instance = GameInstance(name: "Leased", gameVersion: "1.21.1"); instance.directoryID = directory.id
        var state = PersistentState(); state.gameDirectories = [directory]; state.instances = [instance]
        try StateStore.save(state, to: base)
        let paths = base.configured(with: state)
        var lease: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
        let moved = root.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: directory.url, to: moved)
        #expect(throws: (any Error).self) { try GameDirectoryStore.relocate(directory.id, to: moved, paths: base) }
        #expect(try StateStore.load(base).gameDirectories?.first?.url == directory.url)
        withExtendedLifetime(lease) {}; lease = nil
        try GameDirectoryStore.relocate(directory.id, to: moved, paths: base)
        #expect(try StateStore.load(base).gameDirectories?.first?.url == moved.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func detachedMonitorKeepsExternalLocationAfterSelectionChanges() async throws {
        let (root, base, directory) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var instance = GameInstance(name: "目录监控", gameVersion: "fixture"); instance.directoryID = directory.id
        var state = PersistentState(); state.gameDirectories = [directory]; state.instances = [instance]; state.selectedDirectoryID = directory.id
        let paths = base.configured(with: state)
        try paths.prepareInstance(instance.id)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        let helper = TestPaths.monitorExecutable
        let plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "pwd; sleep 0.3; echo external-game-finished"], directory: paths.game(instance.id), environment: ["PATH": "/bin:/usr/bin"])
        try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: helper)
        state.selectedDirectoryID = nil
        let reconnected = base.configured(with: state)
        let finished = try await GameMonitorClient.wait(paths: reconnected, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.exit?.status == 0)
        #expect(!FileManager.default.fileExists(atPath: base.instance(instance.id).path))
        let log = try GameSessionStore.logTail(paths: reconnected, session: finished)
        #expect(log.contains(paths.game(instance.id).path) && log.contains("external-game-finished"))
        #expect(paths.monitorSnapshot(for: instance.id).directories.first?.bookmark == nil)
    }
}
