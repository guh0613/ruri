import Foundation
import Testing
@testable import RuriCore

struct InstanceMoveTests {
    @Test(arguments: [GameRunDirectory.isolated, .shared, .custom])
    @MainActor func movesCompleteInstancesAndKeepsTheSameIdentityAndHistory(mode: GameRunDirectory) async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: mode); defer { fixture.cleanup() }
        let (paths, source) = (fixture.paths, fixture.source)
        let recorder = try GameSessionRecorder(paths: paths, instance: source, accountMode: "offline")
        try recorder.append("History before moving"); try recorder.fail(CancellationError(), cancelled: true)
        let oldHistory = try Data(contentsOf: recorder.directory.appendingPathComponent("session.json"))
        let pack = InstalledModpack(format: "Modrinth", name: "Fixture", version: "1", origin: .init(provider: .modrinth, projectID: "fixture", versionID: "v1"), settings: source, files: [])
        try ModpackRegistry.save(pack, paths: paths, instanceID: source.id)
        try FileExtendedAttributesTests.set(Data("instance label".utf8), at: paths.instance(source.id))
        try FileExtendedAttributesTests.set(Data("game label".utf8), at: paths.game(source.id))
        try FileExtendedAttributesTests.set(Data("pack label".utf8), at: paths.instance(source.id).appendingPathComponent("modpack-state.json"))
        let rootAttributes = try FileExtendedAttributes.capture(paths.instance(source.id))
        let gameAttributes = try FileExtendedAttributes.capture(paths.game(source.id))
        let packAttributes = try FileExtendedAttributes.capture(paths.instance(source.id).appendingPathComponent("modpack-state.json"))
        if mode == .shared { try fixture.write("dormant world", "minecraft/saves/Old/level.dat", in: paths.instance(source.id)) }
        let service = InstanceMover(paths: paths)
        let preview = try await service.preview(instanceID: source.id, directoryID: fixture.target.id)
        let originalGame = mode == .isolated ? nil : try FileTreeManifest.capture(in: paths.game(source.id))
        try StateStore.update(paths) { $0.settings.defaultMemoryMB = 6144 }
        let result = try await service.move(preview), current = paths.configured(with: result.state)
        #expect(result.state.instances == [preview.moved])
        #expect(result.state.schemaVersion == 11 && result.state.settings.defaultMemoryMB == 6144)
        #expect(result.state.selectedInstanceID == source.id && result.state.selectedDirectoryID == fixture.target.id)
        #expect(result.preservedFiles.isEmpty && result.warning == nil)
        #expect(!FileManager.default.fileExists(atPath: preview.sourceDirectory.path))
        #expect(try Data(contentsOf: GameSessionStore.directory(paths: current, instanceID: source.id, sessionID: recorder.record.id).appendingPathComponent("session.json")) == oldHistory)
        #expect(try String(contentsOf: current.game(source.id).appendingPathComponent("options.txt"), encoding: .utf8) == "options")
        #expect(try String(contentsOf: current.game(source.id).appendingPathComponent(".ruri-partials/kept.bin"), encoding: .utf8) == "partial")
        #expect(try String(contentsOf: current.game(source.id).appendingPathComponent(".DS_Store"), encoding: .utf8) == "finder data")
        #expect(try String(contentsOf: current.gameDataState(source.id).appendingPathComponent("world-backups/original.zip"), encoding: .utf8) == "backup")
        let movedPack = try #require(try ModpackRegistry.load(paths: current, instanceID: source.id))
        #expect(movedPack.origin == pack.origin && movedPack.settings.id == source.id && movedPack.settings.directoryID == fixture.target.id)
        #expect(movedPack.settings.runDirectory == preview.moved.runDirectory)
        #expect(try FileExtendedAttributes.capture(current.instance(source.id)) == rootAttributes)
        #expect(try FileExtendedAttributes.capture(current.game(source.id)) == gameAttributes)
        #expect(try FileExtendedAttributes.capture(current.instance(source.id).appendingPathComponent("modpack-state.json")) == packAttributes)
        #expect(!InstanceMoveGuard.hasPending(paths: current, instanceID: source.id))
        #expect(try await service.pending(instanceID: source.id) == nil)
        if let originalGame { try originalGame.requireMatch(in: paths.game(source.id)) }
        if let prior = preview.preservedPreviousData {
            #expect(try String(contentsOf: prior.appendingPathComponent("minecraft/saves/Old/level.dat"), encoding: .utf8) == "dormant world")
        }
        let lease = try GameRunLease.acquire(paths: current, instanceID: source.id)
        withExtendedLifetime(lease) {}
        #expect(throws: (any Error).self) { try paths.prepareInstance(source.id) }
        #expect(!FileManager.default.fileExists(atPath: preview.sourceDirectory.path))
    }

    @Test(arguments: [InstanceMoveProgress.Phase.copying, .publishing])
    func cancellationKeepsOriginalBindingAndDiscoverableWork(phase: InstanceMoveProgress.Phase) async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let operation = Task {
            try await service.move(preview) { update in
                if update.phase == phase { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await operation.value; Issue.record("Cancelled move unexpectedly succeeded") }
        catch let error as InstanceMoveFailure {
            #expect(error.cancelled && !error.preservedFiles.isEmpty)
            #expect(error.preservedFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        #expect(try StateStore.load(fixture.paths).instances == [fixture.source])
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
        #expect(!InstanceMoveGuard.hasPending(paths: fixture.paths, instanceID: fixture.source.id))
    }

    @Test func committedMoveRetainsSourceWhenTargetChangesUntilItCanBeVerified() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let targetFile = preview.destinationGame.appendingPathComponent("options.txt")
        let result = try await service.move(preview) { update in
            if update.phase == .committed { try? Data("changed".utf8).write(to: targetFile) }
        }
        #expect(result.warning != nil && result.state.instances == [preview.moved])
        #expect(try await service.pending(instanceID: fixture.source.id)?.committed == true)
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        await #expect(throws: (any Error).self) { try await service.recover(instanceID: fixture.source.id, transactionID: preview.id) }
        #expect(throws: (any Error).self) { try GameDirectoryStore.remove(fixture.target.id, paths: fixture.paths) }
        let current = fixture.paths.configured(with: result.state)
        await #expect(throws: (any Error).self) { try await ContentManager(paths: current, instanceID: fixture.source.id).records() }
        try Data("options".utf8).write(to: targetFile)
        let recovered = try await service.recover(instanceID: fixture.source.id, transactionID: preview.id)
        #expect(recovered.warning == nil && recovered.preservedFiles.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: preview.sourceDirectory.path))
        #expect(!InstanceMoveGuard.hasPending(paths: current, instanceID: fixture.source.id))
    }

    @Test(arguments: ["source", "destination", "root-attributes"])
    func olderReceiptsCanFinishOnlyWhilePreservingTheSource(missing: String) async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        try FileExtendedAttributesTests.set(Data("keep source metadata".utf8), at: fixture.paths.instance(fixture.source.id))
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let operation = Task {
            try await service.move(preview) { update in
                if update.phase == .committed { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        #expect(try await operation.value.warning != nil)
        let root = try InstanceMoveJournal.root(paths: fixture.paths, instanceID: fixture.source.id)
        let journalFile = root.appendingPathComponent("transaction.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journalFile)) as? [String: Any])
        let name = missing == "destination" ? "destination" : "source"
        let key = name + "Digest", file = root.appendingPathComponent(name + ".json")
        let receipt = try FileTreeManifest.load(from: file, expectedDigest: #require(json[key] as? String))
        let old = FileTreeManifest(version: missing == "root-attributes" ? 2 : 1, entries: receipt.entries.map { entry in
            var copy = entry
            if missing != "root-attributes" { copy.attributes = nil }
            return copy
        })
        json[key] = try old.save(to: file)
        try JSONSerialization.data(withJSONObject: json).write(to: journalFile, options: .atomic)
        await #expect(throws: (any Error).self) { try await service.recover(instanceID: fixture.source.id, transactionID: preview.id) }
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        #expect(try await service.pending(instanceID: fixture.source.id)?.committed == true)
        let completed = try await service.recover(instanceID: fixture.source.id, transactionID: preview.id, preservingSource: true)
        #expect(completed.preservedFiles.contains(preview.sourceDirectory))
        #expect(!InstanceMoveGuard.hasPending(paths: fixture.paths, instanceID: fixture.source.id))
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
    }

    @Test func changedSourceCanBeExplicitlyKeptWhileCompletingTheMove() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let addition = preview.sourceDirectory.appendingPathComponent("added-after-commit.txt")
        let result = try await service.move(preview) { update in
            if update.phase == .committed { try? Data("keep this".utf8).write(to: addition) }
        }
        #expect(result.warning != nil)
        await #expect(throws: (any Error).self) { try await service.recover(instanceID: fixture.source.id, transactionID: preview.id) }
        let recovered = try await service.recover(instanceID: fixture.source.id, transactionID: preview.id, preservingSource: true)
        #expect(recovered.preservedFiles.contains(preview.sourceDirectory) && recovered.warning != nil)
        #expect(InstanceMoveGuard.preservedWorkspaces(paths: fixture.paths, instanceID: fixture.source.id).map(\.path).contains(preview.sourceDirectory.path))
        #expect(try String(contentsOf: addition, encoding: .utf8) == "keep this")
        #expect(!InstanceMoveGuard.hasPending(paths: fixture.paths, instanceID: fixture.source.id))
        #expect(throws: (any Error).self) { try fixture.paths.prepareInstance(fixture.source.id) }
    }

    @Test(arguments: ["partial", "parent-removed", "changed"])
    func interruptedDeletionChecksRemainingFilesAndHandlesAnAlreadyRemovedParent(caseName: String) async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let operation = Task {
            try await service.move(preview) { update in
                if update.phase == .deleting { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let result = try await operation.value
        #expect(result.warning != nil)
        let pending = try #require(try await service.pending(instanceID: fixture.source.id))
        let retired = try #require(pending.retiredSource)
        let record = try InstanceMoveJournal.load(paths: fixture.paths, instanceID: fixture.source.id)
        #expect(record.phase == .deleting && FileManager.default.fileExists(atPath: retired.path))
        #expect(!FileManager.default.fileExists(atPath: preview.sourceDirectory.path))
        try FileManager.default.removeItem(at: retired.appendingPathComponent("minecraft/options.txt"))
        if caseName == "changed" { try fixture.write("new data", "new.txt", in: retired) }
        if caseName == "parent-removed" { try FileManager.default.removeItem(at: retired.deletingLastPathComponent()) }
        if caseName == "changed" {
            await #expect(throws: (any Error).self) { try await service.recover(instanceID: fixture.source.id, transactionID: preview.id) }
            let kept = try await service.recover(instanceID: fixture.source.id, transactionID: preview.id, preservingSource: true)
            #expect(kept.preservedFiles.contains(retired.deletingLastPathComponent()))
            #expect(try String(contentsOf: retired.appendingPathComponent("new.txt"), encoding: .utf8) == "new data")
        } else {
            let recovered = try await service.recover(instanceID: fixture.source.id, transactionID: preview.id)
            #expect(recovered.warning == nil && !FileManager.default.fileExists(atPath: retired.path))
        }
        #expect(!InstanceMoveGuard.hasPending(paths: fixture.paths, instanceID: fixture.source.id))
    }

    @Test func foreignPublicationTargetsAndChangedPreviewSettingsAreNeverReplaced() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        do {
            _ = try await service.move(preview) { update in
                if update.phase == .publishing { try? fixture.write("foreign", "user.txt", in: preview.destination) }
            }
            Issue.record("Foreign directory was replaced")
        } catch let failure as InstanceMoveFailure {
            #expect(!failure.cancelled && failure.preservedFiles.map(\.path).contains(preview.destination.path))
        }
        #expect(try String(contentsOf: preview.destination.appendingPathComponent("user.txt"), encoding: .utf8) == "foreign")
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        #expect(try StateStore.load(fixture.paths).instances == [fixture.source])
        try FileManager.default.removeItem(at: preview.destination)
        let fresh = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        try StateStore.update(fixture.paths) { $0.instances[0].name = "Changed name" }
        await #expect(throws: (any Error).self) { try await service.move(fresh) }
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
    }

    @Test @MainActor func sharedReservationsNoLongerPointAtRetiredHistory() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .shared); defer { fixture.cleanup() }
        let source = fixture.source
        let recorder = try GameSessionRecorder(paths: fixture.paths, instance: source, accountMode: "offline")
        try recorder.fail(CancellationError(), cancelled: true)
        struct Reservation: Encodable { let version = 2; let paths: LauncherPaths; let instanceID: UUID; let sessionID: UUID }
        let reservation = fixture.paths.gameDataState(source.id).appendingPathComponent("active-session.json")
        try JSONEncoder().encode(Reservation(paths: fixture.paths.monitorSnapshot(for: source.id), instanceID: source.id, sessionID: recorder.record.id)).write(to: reservation)
        var alias = GameInstance(name: "Shared sibling", gameVersion: "1.21.1"); alias.runDirectory = .shared
        try StateStore.update(fixture.paths) { $0.instances.append(alias) }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: source.id, directoryID: fixture.target.id)
        let result = try await service.move(preview)
        #expect(result.warning == nil && !FileManager.default.fileExists(atPath: reservation.path))
        let lease = try GameRunLease.acquire(paths: fixture.paths.configured(with: result.state), instanceID: alias.id)
        withExtendedLifetime(lease) {}
        #expect(!FileManager.default.fileExists(atPath: preview.sourceDirectory.path))
    }

    @Test func corruptedReceiptsPreventSourceDeletionAndFullPublicationKeepsHiddenFiles() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let receipt = try InstanceMoveJournal.root(paths: fixture.paths, instanceID: fixture.source.id).appendingPathComponent("source.json")
        let result = try await service.move(preview) { update in
            if update.phase == .committed { try? Data("{}".utf8).write(to: receipt) }
        }
        #expect(result.warning != nil)
        await #expect(throws: (any Error).self) { try await service.recover(instanceID: fixture.source.id, transactionID: preview.id) }
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        // Force the non-rename path used on ExFAT without a mounted volume.
        let publication = fixture.root.appendingPathComponent("publication")
        try RunDirectoryFileCopy.copyForPublication(preview.destination, to: publication, directory: true, ignoringTransientFiles: false, created: { _ in }, validate: {}, progress: { _ in })
        try FileTreeManifest.capture(in: preview.destination).requireMatch(in: publication)
        #expect(FileManager.default.fileExists(atPath: publication.appendingPathComponent("minecraft/.ruri-partials/kept.bin").path))
    }

    @Test(arguments: [false, true])
    func uncommittedRecoveryReturnsPartialPublicationWithoutNeedingTheSharedGame(partialPublication: Bool) async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .custom); defer { fixture.cleanup() }
        let (paths, source) = (fixture.paths, fixture.source)
        var alias = GameInstance(name: "Custom sibling", gameVersion: source.gameVersion)
        alias.runDirectory = .custom; alias.customRunDirectory = source.customRunDirectory
        let state = try StateStore.update(paths) { $0.instances.append(alias) }
        let current = paths.configured(with: state)
        let service = InstanceMover(paths: paths)
        let preview = try await service.preview(instanceID: source.id, directoryID: fixture.target.id)
        let root = try InstanceMoveJournal.root(paths: paths, instanceID: source.id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var record = InstanceMoveJournal(id: preview.id, original: source, moved: preview.moved,
                                         sourceCollection: preview.sourceCollection, targetCollection: preview.targetCollection,
                                         createdAt: Date(), sourceIdentity: preview.sourceIdentity,
                                         sourceDigest: try preview.snapshot.original.save(to: root.appendingPathComponent("source.json")))
        let workspace = try record.workspace(paths: paths), incoming = try record.incoming(paths: paths)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        record.workspaceIdentity = try .read(workspace)
        try RunDirectoryFileCopy.entries(preview.snapshot.entries, to: incoming, validate: {}) { _, _ in }
        record.destinationDigest = try preview.snapshot.destination.save(to: root.appendingPathComponent("destination.json"))
        record.stagedIdentity = try .read(incoming); record.phase = .publishing; try record.save(paths: paths)
        enum Interrupted: Error { case publication }
        if partialPublication {
            #expect(throws: Interrupted.self) {
                try RunDirectoryFileCopy.copyForPublication(incoming, to: preview.destination, directory: true, ignoringTransientFiles: false) { identity in
                    record.publishedIdentity = identity; try record.save(paths: paths)
                    throw Interrupted.publication
                } validate: {} progress: { _ in }
            }
        }
        #expect(try await service.pending(instanceID: source.id)?.committed == false)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: current, instanceID: source.id) }
        #expect(throws: (any Error).self) { try InstanceMoveGuard.requireDirectoryAvailable(fixture.target.id, paths: current) }
        let sibling = try GameRunLease.acquire(paths: current, instanceID: alias.id)
        defer { withExtendedLifetime(sibling) {} }
        let recovered = try await service.recover(instanceID: source.id, transactionID: preview.id)
        #expect(recovered.state.instances.first(where: { $0.id == source.id }) == source)
        #expect(recovered.preservedFiles.map(\.path).contains(workspace.path))
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        #expect(!InstanceMoveGuard.hasPending(paths: current, instanceID: source.id))
    }

    @Test func canMoveBackToDefaultAndCopyAMovedInstanceWithoutInheritingItsReceipt() async throws {
        let fixture = try InstanceMovePreviewTests.Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let first = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let moved = try await service.move(first)
        let copy = try await InstanceCopier(paths: fixture.paths).preview(instanceID: fixture.source.id, name: "Copy after move", directoryID: GameDirectory.defaultID)
        #expect(copy.copy.lastInstanceMoveID == nil && copy.copy.id != fixture.source.id)
        let back = try await service.preview(instanceID: fixture.source.id, directoryID: GameDirectory.defaultID)
        #expect(back.source == moved.state.instances[0])
        let returned = try await service.move(back)
        #expect(returned.warning == nil && returned.state.instances == [back.moved])
        #expect(back.moved.id == fixture.source.id && back.moved.lastInstanceMoveID == back.id)
        #expect(try String(contentsOf: fixture.paths.game(fixture.source.id).appendingPathComponent("options.txt"), encoding: .utf8) == "options")
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.target.url.appendingPathComponent("instances").path).isEmpty)
    }
}
