import Foundation
import Testing
@testable import RuriCore

struct CustomRunDirectoryRelocationTests {
    private func fixture() throws -> (LauncherPaths, GameInstance, CustomRunDirectory, URL) {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-custom-relocate-\(UUID())")
        let paths = LauncherPaths(root: parent.appendingPathComponent("data")), game = parent.appendingPathComponent("Game 中文"), folder = parent.appendingPathComponent("Other collection")
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let custom = try CustomRunDirectory.register(at: game, paths: paths)
        let collection = try GameDirectory.create(name: "Other", at: folder, paths: paths)
        var a = GameInstance(name: "A", gameVersion: "1.21.1"); a.runDirectory = .custom; a.customRunDirectory = custom
        var b = GameInstance(name: "B", gameVersion: "1.21.1"); b.runDirectory = .custom; b.customRunDirectory = custom; b.directoryID = collection.id
        var c = GameInstance(name: "Remembered", gameVersion: "1.21.1"); c.customRunDirectory = custom
        var state = PersistentState(); state.instances = [a, b, c]; state.gameDirectories = [collection]
        let saved = try StateStore.save(state, to: paths)
        try Data("game options".utf8).write(to: game.appendingPathComponent("options.txt"))
        return (paths.configured(with: saved), a, custom, parent.appendingPathComponent("Moved game"))
    }

    @Test func rebindsEveryMatchingAliasAndPreservesFilesHistoryAndConcurrentSettings() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        try FileManager.default.moveItem(at: custom.url, to: moved)
        // A different folder can appear at the old path; it is not touched.
        try FileManager.default.createDirectory(at: custom.url, withIntermediateDirectories: false)
        try Data("foreign".utf8).write(to: custom.url.appendingPathComponent("options.txt"))
        let service = CustomRunDirectoryRelocation(paths: paths), before = try Data(contentsOf: paths.state)
        let preview = try await service.preview(instanceID: a.id, target: moved)
        #expect(preview.instances.count == 3 && preview.instances.filter(\.usesDirectory).count == 2)
        #expect(try Data(contentsOf: paths.state) == before)
        try StateStore.update(paths) { $0.settings.defaultMemoryMB = 8192; $0.instances[0].name = "Renamed elsewhere" }
        let state = try await service.apply(preview), current = paths.configured(with: state)
        #expect(state.instances.allSatisfy { $0.customRunDirectory?.url.path == moved.path })
        #expect(state.instances[0].name == "Renamed elsewhere" && state.settings.defaultMemoryMB == 8192)
        #expect(state.instances[2].runDirectory == nil)
        for item in state.instances { #expect(current.instance(item.id) == paths.instance(item.id)) }
        #expect(try String(contentsOf: moved.appendingPathComponent("options.txt"), encoding: .utf8) == "game options")
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "foreign")
        let lease = try GameRunLease.acquire(paths: current, instanceID: a.id); withExtendedLifetime(lease) {}
    }

    @Test func doesNotRetargetARememberedCopyAndRejectsAnAccessibleOriginal() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        try FileManager.default.copyItem(at: custom.url, to: moved)
        let service = CustomRunDirectoryRelocation(paths: paths)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: moved) }
        try StateStore.update(paths) { $0.instances[2].customRunDirectory?.url = moved; $0.instances[2].customRunDirectory?.bookmark = nil }
        let relocated = moved.deletingLastPathComponent().appendingPathComponent("Actual move")
        try FileManager.default.moveItem(at: custom.url, to: relocated)
        let preview = try await service.preview(instanceID: a.id, target: relocated)
        #expect(preview.instances.count == 2)
        let state = try await service.apply(preview)
        #expect(state.instances[2].customRunDirectory?.url == moved)
        #expect(state.instances[0].customRunDirectory?.url.path == relocated.path)
    }

    @Test func holdsBothInstanceAndMovedRootLocksAndRechecksThemAtCommit() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        var lease: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: a.id)
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let service = CustomRunDirectoryRelocation(paths: paths)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: moved) }
        withExtendedLifetime(lease) {}; lease = nil
        let preview = try await service.preview(instanceID: a.id, target: moved)
        var metadata = a; metadata.runDirectory = .isolated
        lease = try GameRunLease.acquire(paths: paths.including(metadata), instanceID: a.id)
        await #expect(throws: (any Error).self) { try await service.apply(preview) }
        withExtendedLifetime(lease) {}; lease = nil
        let changed = try await service.apply(preview)
        #expect(changed.instances[0].customRunDirectory?.url.path == moved.path)
    }

    @Test func refusesFileOperationsPendingCopyAndUnfinishedWorldTransactions() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let record = RunDirectoryCopyJournal(id: UUID(), original: a, target: .isolated, createdAt: Date(), phase: .copying, items: [], emptyDirectories: [])
        let journal = try RunDirectoryCopyJournal.root(paths: paths, instanceID: a.id)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true); try record.save(paths: paths)
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let service = CustomRunDirectoryRelocation(paths: paths)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: moved) }
        try FileManager.default.removeItem(at: journal)
        for name in [".content-operation.lock", ".world-operation.lock", ".location-registration.lock"] {
            let lock = GameDataOperationLock(); try lock.acquire(directory: moved.appendingPathComponent(".ruri"), name: name)
            await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: moved) }
            lock.release()
        }
        let transaction = moved.appendingPathComponent(".ruri/world-restore")
        try FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: false)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: moved) }
        try FileManager.default.removeItem(at: transaction)
        _ = try await service.preview(instanceID: a.id, target: moved)
    }

    @Test func rejectsChangedAliasesAndTargetsInsteadOfApplyingAStalePreview() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let service = CustomRunDirectoryRelocation(paths: paths)
        let preview = try await service.preview(instanceID: a.id, target: moved)
        try StateStore.update(paths) { $0.instances[1].runDirectory = .isolated }
        await #expect(throws: (any Error).self) { try await service.apply(preview) }
        let fresh = try await service.preview(instanceID: a.id, target: moved)
        let copy = moved.deletingLastPathComponent().appendingPathComponent("Copy")
        try FileManager.default.copyItem(at: moved, to: copy)
        try FileManager.default.moveItem(at: moved, to: moved.deletingLastPathComponent().appendingPathComponent("Original saved"))
        try FileManager.default.moveItem(at: copy, to: moved)
        await #expect(throws: (any Error).self) { try await service.apply(fresh) }
        #expect(try StateStore.load(paths).instances[0].customRunDirectory?.url == custom.url)
    }

    @Test @MainActor func movedReservationStillChecksTheOwningSessionEvenInAnotherLauncherDataRoot() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let otherBase = LauncherPaths(root: paths.root.deletingLastPathComponent().appendingPathComponent("Other launcher"))
        var other = GameInstance(name: "Outside owner", gameVersion: "1.21.1"); other.runDirectory = .custom; other.customRunDirectory = custom
        var state = PersistentState(); state.instances = [other]; try StateStore.save(state, to: otherBase)
        let recorder = try GameSessionRecorder(paths: otherBase.configured(with: state), instance: other, accountMode: "offline")
        try recorder.close() // Reservation persists even without a live OS lock.
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let service = CustomRunDirectoryRelocation(paths: paths)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: a.id, target: moved) }
        try recorder.fail(RuriError.message("Cancelled preparation fixture"), cancelled: true)
        let preview = try await service.preview(instanceID: a.id, target: moved)
        let changed = try await service.apply(preview)
        let next = try GameRunLease.acquire(paths: paths.configured(with: changed), instanceID: a.id)
        withExtendedLifetime(next) {}
        #expect(try GameSessionStore.load(paths: otherBase, instanceID: other.id, sessionID: recorder.record.id).state == .cancelled)
    }

    @Test func concurrentLocationEditsCannotMixOnePathWithAnotherBookmark() throws {
        let (paths, _, _, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let baseline = try StateStore.load(paths)
        var local = baseline; local.instances[2].customRunDirectory?.bookmark = Data("new bookmark".utf8)
        try StateStore.update(paths) { $0.instances[2].customRunDirectory?.url = moved }
        #expect(throws: (any Error).self) { try StateStore.save(local, to: paths, basedOn: baseline) }
        #expect(try StateStore.load(paths).instances[2].customRunDirectory?.url == moved)
    }

    @Test func automaticBookmarkFollowingUsesTheSameLocksAndDoesNotRewriteUnchangedState() async throws {
        let (paths, a, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        var lease: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: a.id)
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let service = CustomRunDirectoryRelocation(paths: paths), initial = try StateStore.load(paths)
        let busy = try await service.resolveBookmarks()
        #expect(busy == initial)
        withExtendedLifetime(lease) {}; lease = nil
        let resolved = try await service.resolveBookmarks()
        #expect(resolved.instances.allSatisfy { $0.customRunDirectory?.url.path == moved.path })
        #expect(resolved.revision != initial.revision)
        #expect(try await service.resolveBookmarks() == resolved)
    }

    @Test func automaticResolutionCanFindBothMovedMetadataAndCustomGameFolders() async throws {
        let (paths, _, custom, moved) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let initial = try StateStore.load(paths), folder = try #require(initial.gameDirectories?.first)
        let movedMetadata = folder.url.deletingLastPathComponent().appendingPathComponent("Moved metadata")
        try FileManager.default.moveItem(at: folder.url, to: movedMetadata)
        try FileManager.default.moveItem(at: custom.url, to: moved)
        let metadata = try GameDirectoryStore.resolveBookmarks(paths: paths)
        #expect(metadata.gameDirectories?.first?.url.path == movedMetadata.path)
        let resolved = try await CustomRunDirectoryRelocation(paths: paths).resolveBookmarks()
        #expect(resolved.instances.allSatisfy { $0.customRunDirectory?.url.path == moved.path })
        for instance in resolved.instances where instance.runDirectory == .custom {
            let lease = try GameRunLease.acquire(paths: paths.configured(with: resolved), instanceID: instance.id)
            withExtendedLifetime(lease) {}
        }
    }

    @Test @MainActor func movedSharedCollectionCanValidateAnOldFinishedReservationWithoutLosingItsHistory() throws {
        let (paths, _, _, _) = try fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let folder = try #require(StateStore.load(paths).gameDirectories?.first)
        var shared = GameInstance(name: "Shared history", gameVersion: "1.21.1"); shared.directoryID = folder.id; shared.runDirectory = .shared
        let initial = try StateStore.update(paths) { $0.instances.append(shared) }, current = paths.configured(with: initial)
        let recorder = try GameSessionRecorder(paths: current, instance: shared, accountMode: "offline")
        let marker = current.gameDataState(shared.id).appendingPathComponent("active-session.json")
        let reservation = try Data(contentsOf: marker)
        try recorder.fail(RuriError.message("fixture ended"), cancelled: true)
        try reservation.write(to: marker)
        let moved = folder.url.deletingLastPathComponent().appendingPathComponent("Moved shared collection")
        try FileManager.default.moveItem(at: folder.url, to: moved)
        let updated = try GameDirectoryStore.relocate(folder.id, to: moved, paths: paths), relocated = paths.configured(with: updated)
        let lease = try GameRunLease.acquire(paths: relocated, instanceID: shared.id); withExtendedLifetime(lease) {}
        #expect(try GameSessionStore.load(paths: relocated, instanceID: shared.id, sessionID: recorder.record.id).state == .cancelled)
    }
}
