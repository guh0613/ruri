import Foundation
import Darwin
import Testing
@testable import RuriCore

struct GameRunDirectoryCopyTests {
    private func fixture(withData: Bool = true, withContent: Bool = false) async throws -> (LauncherPaths, GameInstance, GameInstance, GameRunDirectoryChangePreview) {
        let base = LauncherPaths(root: FileManager.default.temporaryDirectory.appendingPathComponent("ruri-copy-\(UUID())"))
        let a = GameInstance(name: "Copy source", gameVersion: "1.21.1")
        var b = GameInstance(name: "Shared target", gameVersion: "1.21.1"); b.runDirectory = .shared
        var state = PersistentState(); state.instances = [a, b]; try StateStore.save(state, to: base)
        let paths = base.configured(with: state)
        try FileManager.default.createDirectory(at: paths.game(a.id), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.game(b.id).appendingPathComponent("mods/empty-folder"), withIntermediateDirectories: true)
        if withData {
            try Data("source-options".utf8).write(to: paths.game(a.id).appendingPathComponent("options.txt"))
        }
        if withContent {
            let jar = paths.cache.appendingPathComponent("mod.jar"); try Data("fixture-mod".utf8).write(to: jar)
            let record = ManagedContent(projectID: "fixture", versionID: "v1", title: "Fixture Mod", versionName: "1", kind: .mod, filename: "fixture.jar", size: 11, requiredProjects: [])
            try await ContentManager(paths: paths, instanceID: a.id).install([.init(record: record, source: jar)])
            let world = paths.game(a.id).appendingPathComponent("saves/World")
            try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
            try WorldTests().nbt().write(to: world.appendingPathComponent("level.dat"))
            _ = try await WorldManager(paths: paths, instanceID: a.id).backup(folder: "World")
        }
        return (paths, a, b, try await GameRunDirectoryChange(paths: paths).preview(instanceID: a.id, target: .shared))
    }
    private func journal(_ preview: GameRunDirectoryChangePreview, paths: LauncherPaths, published: Bool = false, committed: Bool = false) throws -> RunDirectoryCopyJournal {
        let root = try RunDirectoryCopyJournal.root(paths: paths, instanceID: preview.instanceID)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("incoming/game"), withIntermediateDirectories: true)
        var record = RunDirectoryCopyJournal(id: UUID(), original: preview.instance, target: preview.targetMode, createdAt: Date(), phase: .copying, items: [], emptyDirectories: [])
        var target = preview.instance; target.runDirectory = preview.targetMode
        let destinationPaths = paths.including(target)
        if published {
            let file = root.appendingPathComponent("incoming/game/copied.txt")
            try Data("published-copy".utf8).write(to: file)
            let item = RunDirectoryCopyJournal.Item(area: .game, name: "copied.txt", identity: try .read(file))
            record.items = [item]; record.phase = .publishing; try record.save(paths: paths)
            try RunDirectoryCopyGuard.mark(record, paths: destinationPaths)
            try RunDirectoryFileCopy.moveWithoutReplacing(file, to: record.destination(item, paths: destinationPaths))
        } else { try record.save(paths: paths); try RunDirectoryCopyGuard.mark(record, paths: destinationPaths) }
        if committed {
            try StateStore.update(paths) { state in
                state.instances[0].runDirectory = preview.targetMode
                state.instances[0].lastRunDirectoryChangeID = record.id
            }
        }
        return record
    }

    @Test func copiesGameRecordsAndBackupsAndKeepsTheOriginalIndependent() async throws {
        let (paths, a, b, preview) = try await fixture(withContent: true); defer { try? FileManager.default.removeItem(at: paths.root) }
        #expect(preview.canCopyToTarget)
        let oldBackup = try #require(try await WorldManager(paths: paths, instanceID: a.id).backups().first)
        let oldBackupBytes = try Data(contentsOf: oldBackup.url)
        let result = try await GameRunDirectoryChange(paths: paths).copyToEmpty(preview)
        let current = paths.configured(with: result.state)
        #expect(result.state.instances[0].runDirectory == .shared)
        #expect(!RunDirectoryCopyGuard.hasPending(paths: current, instanceID: a.id))
        #expect(!RunDirectoryCopyGuard.hasPending(paths: current, instanceID: b.id))
        #expect(try await ContentManager(paths: current, instanceID: a.id).records().first?.projectID == "fixture")
        #expect(try await WorldManager(paths: current, instanceID: b.id).worlds().first?.name == "测试世界🐱")
        let newBackup = try #require(try await WorldManager(paths: current, instanceID: a.id).backups().first)
        #expect(try Data(contentsOf: newBackup.url) == oldBackupBytes)
        try Data("changed-copy".utf8).write(to: current.game(a.id).appendingPathComponent("options.txt"))
        #expect(try String(contentsOf: paths.game(a.id).appendingPathComponent("options.txt"), encoding: .utf8) == "source-options")
        #expect(try Data(contentsOf: oldBackup.url) == oldBackupBytes)
        #expect(result.preservedCopy == nil && result.warning == nil)
    }

    @Test func cancellationDuringCopyPreservesWorkspaceAndDoesNotChangeBinding() async throws {
        let (paths, a, b, preview) = try await fixture(withContent: true); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = GameRunDirectoryChange(paths: paths)
        let work = Task {
            try await service.copyToEmpty(preview) { progress in
                if progress.phase == .copying && progress.completed >= 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await work.value; Issue.record("Expected cancellation") }
        catch let failure as RunDirectoryCopyFailure {
            #expect(failure.cancelled)
            let preserved = try #require(failure.preservedCopy)
            #expect(FileManager.default.fileExists(atPath: preserved.appendingPathComponent("incoming/game/options.txt").path))
        }
        #expect(try StateStore.load(paths).instances[0].runDirectory == nil)
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: a.id))
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: b.id))
        #expect(try FileTree.entries(in: paths.game(b.id), excluding: [".ruri"]).allSatisfy(\.directory))
    }

    @Test func cancellationAfterPublicationRollsBackItsFilesAndRestoresEmptyFolders() async throws {
        let (paths, a, b, preview) = try await fixture(withContent: true); defer { try? FileManager.default.removeItem(at: paths.root) }
        let service = GameRunDirectoryChange(paths: paths)
        let work = Task {
            try await service.copyToEmpty(preview) { progress in
                if progress.phase == .publishing && progress.completed == 1 {
                    #expect(RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: b.id))
                    #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: b.id) }
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do { _ = try await work.value; Issue.record("Expected cancellation") }
        catch let failure as RunDirectoryCopyFailure { #expect(failure.cancelled && failure.preservedCopy != nil) }
        #expect(try StateStore.load(paths).instances[0].runDirectory == nil)
        #expect(FileManager.default.fileExists(atPath: paths.game(b.id).appendingPathComponent("mods/empty-folder").path))
        #expect(!FileManager.default.fileExists(atPath: paths.game(b.id).appendingPathComponent("mods/fixture.jar").path))
        #expect(FileManager.default.fileExists(atPath: paths.game(a.id).appendingPathComponent("mods/fixture.jar").path))
    }

    @Test func lateForeignFileIsNeverOverwrittenAndPublishedItemsArePreserved() async throws {
        let (paths, a, b, preview) = try await fixture(withContent: true); defer { try? FileManager.default.removeItem(at: paths.root) }
        let foreign = paths.game(b.id).appendingPathComponent("options.txt")
        do {
            _ = try await GameRunDirectoryChange(paths: paths).copyToEmpty(preview) { progress in
                if progress.phase == .publishing && progress.completed == 0 { try? Data("foreign-options".utf8).write(to: foreign) }
            }
            Issue.record("Expected destination conflict")
        } catch let failure as RunDirectoryCopyFailure {
            let recovery = try #require(failure.preservedCopy)
            #expect(FileManager.default.fileExists(atPath: recovery.appendingPathComponent("incoming/game/mods/fixture.jar").path))
        }
        #expect(try String(contentsOf: foreign, encoding: .utf8) == "foreign-options")
        #expect(try String(contentsOf: paths.game(a.id).appendingPathComponent("options.txt"), encoding: .utf8) == "source-options")
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: b.id))
    }

    @Test func persistentMarkerBlocksOtherClientsAfterAllKernelLocksAreGone() async throws {
        let (paths, a, b, preview) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let pending = try journal(preview, paths: paths, published: true)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: a.id) }
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: b.id) }
        await #expect(throws: (any Error).self) { try await ContentManager(paths: paths, instanceID: b.id).records() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths, instanceID: b.id).worlds() }
        let unrelated = GameInstance(name: "Unrelated", gameVersion: "1.21.1")
        let independent = try GameRunLease.acquire(paths: paths.including(unrelated), instanceID: unrelated.id)
        withExtendedLifetime(independent) {}
        let service = GameRunDirectoryChange(paths: paths)
        #expect(try await service.pendingCopy(instanceID: b.id)?.owner.instanceID == a.id)
        let restored = try await service.recoverCopy(instanceID: a.id, transactionID: pending.id)
        let copy = try #require(restored.preservedCopy)
        #expect(try String(contentsOf: copy.appendingPathComponent("incoming/game/copied.txt"), encoding: .utf8) == "published-copy")
        #expect(!FileManager.default.fileExists(atPath: paths.game(b.id).appendingPathComponent("copied.txt").path))
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: b.id))
    }

    @Test func stateCommitReceiptPreventsRollbackWhenJournalWasNotYetUpdated() async throws {
        let (paths, a, b, preview) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let pending = try journal(preview, paths: paths, published: true, committed: true)
        let service = GameRunDirectoryChange(paths: paths)
        #expect(try await service.pendingCopy(instanceID: a.id)?.committed == true)
        let result = try await service.recoverCopy(instanceID: a.id, transactionID: pending.id)
        #expect(result.state.instances[0].runDirectory == .shared && result.preservedCopy == nil)
        #expect(try String(contentsOf: paths.game(b.id).appendingPathComponent("copied.txt"), encoding: .utf8) == "published-copy")
        #expect(FileManager.default.fileExists(atPath: paths.game(a.id).appendingPathComponent("options.txt").path))
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths.configured(with: result.state), instanceID: a.id))
    }

    @Test func recoveryPreservesForeignReplacementAndRejectsStaleOrForgedRecords() async throws {
        let (paths, a, b, preview) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let pending = try journal(preview, paths: paths, published: true)
        let destination = paths.game(b.id).appendingPathComponent("copied.txt")
        try FileManager.default.moveItem(at: destination, to: paths.cache.appendingPathComponent("externally-moved.txt"))
        try Data("foreign-replacement".utf8).write(to: destination)
        let service = GameRunDirectoryChange(paths: paths)
        await #expect(throws: (any Error).self) { try await service.recoverCopy(instanceID: a.id, transactionID: UUID()) }
        let recovered = try await service.recoverCopy(instanceID: a.id, transactionID: pending.id)
        #expect(recovered.warning?.contains("copied.txt") == true)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "foreign-replacement")
        var forged = try journal(preview, paths: paths)
        forged.items = [.init(area: .game, name: "../outside", identity: try .read(destination))]
        try forged.save(paths: paths)
        await #expect(throws: (any Error).self) { try await service.recoverCopy(instanceID: a.id, transactionID: forged.id) }
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func failedTemporaryCleanupRetiresTheJournalAndDoesNotBlockTheCommittedDirectory() async throws {
        let (paths, a, b, preview) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root) }
        let result = try await GameRunDirectoryChange(paths: paths).copyToEmpty(preview) { progress in
            if progress.phase == .committed {
                do {
                    let file = try RunDirectoryCopyJournal.root(paths: paths, instanceID: a.id).appendingPathComponent("incoming/game/cleanup-blocker.txt")
                    try Data("temporary file".utf8).write(to: file)
                    #expect(chflags(file.path, UInt32(UF_IMMUTABLE)) == 0)
                } catch { Issue.record(error) }
            }
        }
        let remainder = try #require(result.preservedCopy)
        let blocker = remainder.appendingPathComponent("incoming/game/cleanup-blocker.txt")
        defer { _ = chflags(blocker.path, 0) }
        #expect(result.warning != nil)
        let current = paths.configured(with: result.state)
        #expect(result.state.instances[0].runDirectory == .shared)
        #expect(!RunDirectoryCopyGuard.hasPending(paths: current, instanceID: a.id))
        #expect(!RunDirectoryCopyGuard.hasPending(paths: current, instanceID: b.id))
        #expect(try String(contentsOf: blocker, encoding: .utf8) == "temporary file")
        #expect(try String(contentsOf: current.game(a.id).appendingPathComponent("options.txt"), encoding: .utf8) == "source-options")
        #expect(try await GameRunDirectoryChange(paths: current).pendingCopy(instanceID: a.id) == nil)
        let lease = try GameRunLease.acquire(paths: current, instanceID: a.id)
        withExtendedLifetime(lease) {}
    }

    @Test func emptyCopySwitchesTheBindingWithoutLeavingAPendingTransaction() async throws {
        let (paths, a, _, preview) = try await fixture(withData: false); defer { try? FileManager.default.removeItem(at: paths.root) }
        let result = try await GameRunDirectoryChange(paths: paths).copyToEmpty(preview)
        #expect(result.state.instances[0].runDirectory == .shared)
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths.configured(with: result.state), instanceID: a.id))
    }

    @Test func streamFallbackCanBeCancelledInsideALargeFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-stream-copy-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("large.bin"), target = root.appendingPathComponent("partial.bin")
        let data = Data(repeating: 0x55, count: 4 * 1_048_576); try data.write(to: source)
        let work = Task {
            try RunDirectoryFileCopy.file(source, to: target, preferClone: false) { _ in withUnsafeCurrentTask { $0?.cancel() } }
        }
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(try Data(contentsOf: source) == data)
        let copiedBytes = try #require(target.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(copiedBytes > 0 && copiedBytes < data.count)
    }
}
