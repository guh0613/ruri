import Foundation
import CryptoKit
import Testing
@testable import RuriCore

struct GameRunDirectoryChangeTests {
    private func fixture() throws -> (LauncherPaths, GameInstance, GameInstance) {
        let base = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-change-\(UUID())"))
        let a = GameInstance(name: "Original", gameVersion: "1.21.1")
        var b = GameInstance(name: "Shared", gameVersion: "1.21.1"); b.runDirectory = .shared
        var state = PersistentState(); state.instances = [a, b]
        try StateStore.save(state, to: base)
        let paths = base.configured(with: state)
        for (instance, text) in [(a, "original-settings"), (b, "shared-settings")] {
            try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: paths.game(instance.id).appendingPathComponent("options.txt"))
        }
        return (paths, a, b)
    }
    @Test func switchingToExistingContentAndBackPreservesBothTreesAndMetadata() async throws {
        let (paths, a, b) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let firstMetadata = paths.gameDataState(a.id).appendingPathComponent("content.json")
        let otherMetadata = paths.gameDataState(b.id).appendingPathComponent("content.json")
        try FileManager.default.createDirectory(at: otherMetadata.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: firstMetadata); try Data("[ ]".utf8).write(to: otherMetadata)
        let service = GameRunDirectoryChange(paths: paths)
        let preview = try await service.preview(instanceID: a.id, target: .shared)
        #expect(!preview.canCopyToTarget)
        #expect(preview.otherInstances == [b.name])
        #expect(try StateStore.load(paths).instances.first?.runDirectory == nil)
        try StateStore.update(paths) { $0.settings.defaultMemorySettings = .init(maximumMB: 8192); $0.instances[0].memoryMB = 6144 }
        let changed = try await service.useExisting(preview)
        #expect(changed.instances[0].runDirectory == .shared && changed.instances[0].memoryMB == 6144 && changed.settings.defaultMemorySettings?.maximumMB == 8192)
        #expect(try String(contentsOf: paths.configured(with: changed).game(a.id).appendingPathComponent("options.txt"), encoding: .utf8) == "shared-settings")
        let back = try await service.preview(instanceID: a.id, target: .isolated)
        let restored = try await service.useExisting(back)
        #expect(restored.instances[0].runDirectory == .isolated)
        #expect(try String(contentsOf: paths.game(a.id).appendingPathComponent("options.txt"), encoding: .utf8) == "original-settings")
        #expect(try String(contentsOf: firstMetadata, encoding: .utf8) == "[]")
        #expect(try String(contentsOf: otherMetadata, encoding: .utf8) == "[ ]")
    }
    @Test func changedSourceTargetOrLocationInvalidateOldPreview() async throws {
        let (paths, a, b) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = GameRunDirectoryChange(paths: paths)
        let before = try await service.preview(instanceID: a.id, target: .shared)
        try Data("new external contents".utf8).write(to: paths.game(b.id).appendingPathComponent("options.txt"))
        await #expect(throws: (any Error).self) { try await service.useExisting(before) }
        let after = try await service.preview(instanceID: a.id, target: .shared)
        try Data("changed original contents".utf8).write(to: paths.game(a.id).appendingPathComponent("options.txt"))
        await #expect(throws: (any Error).self) { try await service.useExisting(after) }
        let changedSource = try await service.preview(instanceID: a.id, target: .shared)
        try StateStore.update(paths) { $0.instances[0].gameVersion = "26.2" }
        await #expect(throws: (any Error).self) { try await service.useExisting(changedSource) }
        #expect(try StateStore.load(paths).instances.first?.runDirectory == nil)
    }
    @Test @MainActor func runningSharedTargetAndUnfinishedSourcePreventSwitching() async throws {
        let (paths, a, b) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = GameRunDirectoryChange(paths: paths)
        let running = try GameSessionRecorder(paths: paths, instance: b, accountMode: "offline")
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: .shared) }
        try running.fail(CancellationError(), cancelled: true)
        let interrupted = try GameSessionRecorder(paths: paths, instance: a, accountMode: "offline")
        try interrupted.close()
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: .shared) }
        _ = try GameSessionRecovery.finish(paths: paths, expected: interrupted.record, userConfirmedEnded: true)
        #expect(try await service.preview(instanceID: a.id, target: .shared).instanceID == a.id)
    }
    @Test func activeFileTransactionAndModpackPreventChangingBinding() async throws {
        let (paths, a, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = GameRunDirectoryChange(paths: paths), lock = GameDataOperationLock()
        try lock.acquire(directory: paths.gameDataState(a.id), name: ".content-operation.lock")
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: .shared) }
        lock.release()
        let pack = InstalledModpack(format: "Modrinth", name: "Fixture Pack", version: "1", origin: nil, settings: a, files: [])
        try ModpackRegistry.save(pack, paths: paths, instanceID: a.id)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: .shared) }
        #expect(try StateStore.load(paths).instances.first?.runDirectory == nil)
    }
    @Test func legacyResourcesArePreparedFromCacheInTheSelectedRunDirectory() async throws {
        let (paths, _, b) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let bytes = Data("legacy-resource".utf8), hash = Insecure.SHA1.hash(data: Data("legacy-resource".utf8)).map { String(format: "%02x", $0) }.joined()
        let object = paths.assets.appendingPathComponent("objects/\(hash.prefix(2))/\(hash)")
        try FileManager.default.createDirectory(at: object.deletingLastPathComponent(), withIntermediateDirectories: true); try bytes.write(to: object)
        let index = paths.assets.appendingPathComponent("indexes/legacy-fixture.json")
        try FileManager.default.createDirectory(at: index.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["map_to_resources": true, "objects": ["sound/fixture.ogg": ["hash": hash, "size": bytes.count]]]).write(to: index)
        let manifest = try JSONDecoder().decode(VersionManifest.self, from: Data(#"{"id":"fixture","libraries":[],"assetIndex":{"id":"legacy-fixture","url":"https://example.invalid/index.json"}}"#.utf8))
        try await GameInstaller(paths: paths).prepareRunDirectory(b, manifest: manifest)
        #expect(try Data(contentsOf: paths.game(b.id).appendingPathComponent("resources/sound/fixture.ogg")) == bytes)
        #expect(!FileManager.default.fileExists(atPath: paths.instance(b.id).appendingPathComponent("minecraft/resources").path))
        #expect(try Data(contentsOf: object) == bytes)
    }
}
