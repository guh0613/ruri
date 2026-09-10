import Foundation
import Testing
@testable import RuriCore

struct InstanceMovePreviewTests {
    struct Fixture {
        let root: URL
        let paths: LauncherPaths
        let source: GameInstance
        let target: GameDirectory

        init(mode: GameRunDirectory) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-move-preview-\(UUID())")
            let base = LauncherPaths(root: root.appendingPathComponent("data")), targetURL = root.appendingPathComponent("Target")
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            target = try GameDirectory.create(name: "Target", at: targetURL, paths: base)
            var instance = GameInstance(name: "Preserved identity", gameVersion: "1.21.1", loader: .fabric, loaderVersion: "0.16.10")
            instance.runDirectory = mode; instance.playTime = 4321; instance.lastPlayed = Date(); instance.favorite = true
            instance.launchOverrides = .init(); instance.extraJVMArguments = "-Dpreserved=true"
            if mode == .custom {
                let game = root.appendingPathComponent("Custom")
                try FileManager.default.createDirectory(at: game, withIntermediateDirectories: false)
                instance.customRunDirectory = try CustomRunDirectory.register(at: game, paths: base)
            }
            source = instance
            var state = PersistentState(); state.instances = [instance]; state.gameDirectories = [target]
            paths = base.configured(with: try StateStore.save(state, to: base))
            try write("options", "options.txt", in: paths.game(instance.id))
            try write("world", "saves/World/region/r.0.0.mca", in: paths.game(instance.id))
            try write("native", "natives/libfixture.dylib", in: paths.instance(instance.id))
            try write("report", "installer.log", in: paths.instance(instance.id))
            try write("[]", "content.json", in: paths.gameDataState(instance.id))
            try write("backup", "world-backups/original.zip", in: paths.gameDataState(instance.id))
            try write("finder data", ".DS_Store", in: paths.game(instance.id))
            try write("partial", ".ruri-partials/kept.bin", in: paths.game(instance.id))
            try FileManager.default.createDirectory(at: paths.instance(instance.id).appendingPathComponent("empty-directory"), withIntermediateDirectories: true)
        }
        func write(_ text: String, _ path: String, in directory: URL) throws {
            let file = directory.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    @Test(arguments: [GameRunDirectory.isolated, .shared, .custom])
    @MainActor func preservesIdentityHistorySettingsAndTheCorrectGameFiles(mode: GameRunDirectory) async throws {
        let fixture = try Fixture(mode: mode); defer { fixture.cleanup() }
        let (paths, source) = (fixture.paths, fixture.source)
        let history = try GameSessionRecorder(paths: paths, instance: source, accountMode: "offline")
        try history.append("preserved history")
        try history.fail(CancellationError(), cancelled: true)
        try GameSessionReviewStore.mark(history.record, paths: paths)
        let service = InstanceMover(paths: paths)
        let preview = try await service.preview(instanceID: source.id, directoryID: fixture.target.id)
        var expected = source; expected.directoryID = fixture.target.id
        if mode == .shared { expected.runDirectory = .isolated; expected.customRunDirectory = nil; expected.lastRunDirectoryChangeID = nil }
        #expect(preview.source == source && preview.moved == expected)
        #expect(preview.sourceDirectory == paths.instance(source.id) && preview.destination != preview.sourceDirectory)
        #expect(preview.fileCount > 0 && preview.bytes > 0)
        #expect((preview.retainedGameDirectory != nil) == (mode != .isolated))
        #expect((preview.destinationGame == preview.sourceGame) == (mode == .custom))
        #expect(preview.preservedPreviousData == nil)
        let staging = fixture.root.appendingPathComponent("staged")
        try RunDirectoryFileCopy.entries(preview.snapshot.entries, to: staging, validate: {}) { _, _ in }
        try preview.snapshot.destination.requireMatch(in: staging)
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        #expect(try Data(contentsOf: staging.appendingPathComponent("sessions/\(history.record.id)/session.json")) == Data(contentsOf: history.directory.appendingPathComponent("session.json")))
        #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("empty-directory").path))
        if mode != .custom {
            #expect(try String(contentsOf: staging.appendingPathComponent("minecraft/.DS_Store"), encoding: .utf8) == "finder data")
            #expect(try String(contentsOf: staging.appendingPathComponent("minecraft/.ruri-partials/kept.bin"), encoding: .utf8) == "partial")
            #expect(try String(contentsOf: staging.appendingPathComponent("world-backups/original.zip"), encoding: .utf8) == "backup")
        } else {
            #expect(!FileManager.default.fileExists(atPath: staging.appendingPathComponent("minecraft").path))
            #expect(!FileManager.default.fileExists(atPath: staging.appendingPathComponent("world-backups").path))
        }
        #expect(try StateStore.load(paths).instances == [source])
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
    }

    @Test func sharedMappingPreservesDormantIsolatedFilesWithoutOverwritingLiveContent() async throws {
        let fixture = try Fixture(mode: .shared); defer { fixture.cleanup() }
        let root = fixture.paths.instance(fixture.source.id)
        try fixture.write("old world", "minecraft/saves/Old/world.dat", in: root)
        try fixture.write("old registry", "content.json", in: root)
        try fixture.write("old backup", "world-backups/original.zip", in: root)
        try fixture.write("older preserved data", "previous-run-directories/older/note.txt", in: root)
        let preview = try await InstanceMover(paths: fixture.paths).preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let staging = fixture.root.appendingPathComponent("staged")
        try RunDirectoryFileCopy.entries(preview.snapshot.entries, to: staging, validate: {}) { _, _ in }
        try preview.snapshot.destination.requireMatch(in: staging)
        let prior = staging.appendingPathComponent(InstanceMoveSnapshot.previousDataPath(preview.id))
        #expect(preview.preservedPreviousData == preview.destination.appendingPathComponent(InstanceMoveSnapshot.previousDataPath(preview.id)))
        #expect(try String(contentsOf: prior.appendingPathComponent("content.json"), encoding: .utf8) == "old registry")
        #expect(try String(contentsOf: prior.appendingPathComponent("minecraft/saves/Old/world.dat"), encoding: .utf8) == "old world")
        #expect(try String(contentsOf: prior.appendingPathComponent("world-backups/original.zip"), encoding: .utf8) == "old backup")
        #expect(try String(contentsOf: staging.appendingPathComponent("content.json"), encoding: .utf8) == "[]")
        #expect(try String(contentsOf: staging.appendingPathComponent("world-backups/original.zip"), encoding: .utf8) == "backup")
        #expect(!FileManager.default.fileExists(atPath: staging.appendingPathComponent("minecraft/.ruri").path))
        try preview.snapshot.original.requireMatch(in: root)
    }

    @Test func rejectsChangedBytesEvenWhenSizeAndModificationDateMatch() async throws {
        let fixture = try Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let file = fixture.paths.game(fixture.source.id).appendingPathComponent("options.txt")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        try Data("OPTIONS".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: file.path)
        await #expect(throws: (any Error).self) { try await service.validate(preview, state: StateStore.load(fixture.paths)) }
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
        let fresh = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let updated = try StateStore.update(fixture.paths) { $0.instances[0].favorite.toggle() }
        await #expect(throws: (any Error).self) { try await service.validate(fresh, state: updated) }
    }

    @Test @MainActor func requiresEveryHistoryRecordToBeReadableAndFinished() async throws {
        let fixture = try Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let recorder = try GameSessionRecorder(paths: fixture.paths, instance: fixture.source, accountMode: "offline")
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        try recorder.close() // Inactive process alone does not finish its history.
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        try recorder.fail(CancellationError(), cancelled: true)
        _ = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let recordFile = recorder.directory.appendingPathComponent("session.json")
        let original = try Data(contentsOf: recordFile)
        try Data("broken history".utf8).write(to: recordFile)
        #expect(try GameSessionStore.list(paths: fixture.paths, instanceID: fixture.source.id).isEmpty)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        try original.write(to: recordFile)
        let identity: ProcessIdentity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        var live = recorder.record; live.gameIdentity = identity
        try JSONEncoder().encode(live).write(to: recordFile)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
    }

    @Test func rejectsSameUnknownOccupiedAndSymlinkTargets() async throws {
        let fixture = try Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: GameDirectory.defaultID) }
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: UUID()) }
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        try fixture.write("foreign", "user.txt", in: preview.destination)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        #expect(try String(contentsOf: preview.destination.appendingPathComponent("user.txt"), encoding: .utf8) == "foreign")
        try FileManager.default.removeItem(at: preview.destination)
        try FileManager.default.createSymbolicLink(at: preview.destination, withDestinationURL: fixture.root.appendingPathComponent("missing"))
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: preview.destination.path) == fixture.root.appendingPathComponent("missing").path)
    }

    @Test func rejectsMovingSharedDataWhileAnAliasHoldsTheRunDirectory() async throws {
        let fixture = try Fixture(mode: .shared); defer { fixture.cleanup() }
        var alias = GameInstance(name: "Other instance", gameVersion: "1.21.1"); alias.runDirectory = .shared
        let state = try StateStore.update(fixture.paths) { $0.instances.append(alias) }
        let paths = fixture.paths.configured(with: state)
        let lease = try GameRunLease.acquire(paths: paths, instanceID: alias.id)
        defer { withExtendedLifetime(lease) {} }
        await #expect(throws: (any Error).self) { try await InstanceMover(paths: paths).preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
    }

    @Test func unrelatedSettingsRemainValidButIdenticalReplacementFoldersDoNot() async throws {
        let fixture = try Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let updated = try StateStore.update(fixture.paths) { $0.settings.defaultMemoryMB = 6144 }
        try await service.validate(preview, state: updated)
        let parked = fixture.root.appendingPathComponent("Original folder")
        try FileManager.default.moveItem(at: preview.sourceDirectory, to: parked)
        try FileManager.default.copyItem(at: parked, to: preview.sourceDirectory)
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        await #expect(throws: (any Error).self) { try await service.validate(preview, state: updated) }
        #expect(FileManager.default.fileExists(atPath: parked.path))
    }

    @Test func sharedFileChangesCancellationAndOfflineTargetsLeaveTheBindingAlone() async throws {
        let fixture = try Fixture(mode: .shared); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        try fixture.write("new file", "config/new.json", in: preview.sourceGame)
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        await #expect(throws: (any Error).self) { try await service.validate(preview, state: StateStore.load(fixture.paths)) }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        try FileManager.default.removeItem(at: fixture.target.url.appendingPathComponent(GameDirectory.markerName))
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        #expect(try StateStore.load(fixture.paths).instances == [fixture.source])
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
    }
}
