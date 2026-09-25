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

    @Test func rejectsChangedBytesEvenWhenSizeAndModificationDateMatch() async throws {
        let fixture = try Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let file = fixture.paths.game(fixture.source.id).appendingPathComponent("options.txt")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        try Data("OPTIONS".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: file.path)
        await #expect(throws: (any Error).self) { try await service.move(preview) }
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
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
        let original = try JSONEncoder().encode(recorder.record)
        try GameHistoryStore.withDatabase(paths: fixture.paths) { db in
            try db.execute("UPDATE sessions SET payload=? WHERE id=?", [.blob(Data("broken history".utf8)), .text(recorder.record.id.uuidString)])
        }
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        try GameHistoryStore.withDatabase(paths: fixture.paths) { db in
            try db.execute("UPDATE sessions SET payload=? WHERE id=?", [.blob(original), .text(recorder.record.id.uuidString)])
        }
        let identity: ProcessIdentity = try #require(ProcessIdentity.read(ProcessInfo.processInfo.processIdentifier))
        var live = recorder.record; live.gameIdentity = identity; live.revision = (live.revision) + 1
        try GameHistoryStore.record(live, paths: fixture.paths)
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

    @Test func replacedSourceFolderInvalidatesTheMoveEvenWhenItsFilesMatch() async throws {
        let fixture = try Fixture(mode: .isolated); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        let parked = fixture.root.appendingPathComponent("Original folder")
        try FileManager.default.moveItem(at: preview.sourceDirectory, to: parked)
        try FileManager.default.copyItem(at: parked, to: preview.sourceDirectory)
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        await #expect(throws: (any Error).self) { try await service.move(preview) }
        #expect(FileManager.default.fileExists(atPath: parked.path))
    }

    @Test func sharedFileChangesAndOfflineTargetsLeaveTheBindingAlone() async throws {
        let fixture = try Fixture(mode: .shared); defer { fixture.cleanup() }
        let service = InstanceMover(paths: fixture.paths)
        let preview = try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id)
        try fixture.write("new file", "config/new.json", in: preview.sourceGame)
        try preview.snapshot.original.requireMatch(in: preview.sourceDirectory)
        await #expect(throws: (any Error).self) { try await service.move(preview) }
        try FileManager.default.removeItem(at: fixture.target.url.appendingPathComponent(GameDirectory.markerName))
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: fixture.source.id, directoryID: fixture.target.id) }
        #expect(try StateStore.load(fixture.paths).instances == [fixture.source])
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
    }
}
