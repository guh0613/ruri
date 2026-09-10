import Foundation
import Testing
@testable import RuriCore

struct InstanceCopyTests {
    private func fixture(mode: GameRunDirectory = .isolated) async throws -> (LauncherPaths, GameInstance, GameDirectory) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-instance-copy-\(UUID())")
        let base = LauncherPaths(root: root.appendingPathComponent("data")), target = root.appendingPathComponent("Target collection")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let collection = try GameDirectory.create(name: "Target", at: target, paths: base)
        var original = GameInstance(name: "Original", gameVersion: "1.21.1")
        original.runDirectory = mode; original.installed = true; original.playTime = 123; original.lastPlayed = Date(); original.favorite = true
        original.launchOverrides = .init(); original.extraJVMArguments = "-Dfixture=preserved"
        if mode == .custom {
            let game = root.appendingPathComponent("Custom game"); try FileManager.default.createDirectory(at: game, withIntermediateDirectories: false)
            original.customRunDirectory = try CustomRunDirectory.register(at: game, paths: base)
        }
        var state = PersistentState(); state.instances = [original]; state.gameDirectories = [collection]; state.settings.defaultMemoryMB = 2048
        let saved = try StateStore.save(state, to: base), paths = base.configured(with: saved)
        func write(_ text: String, _ relative: String, at root: URL) throws {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        try write("{\"id\":\"1.21.1\",\"mainClass\":\"net.minecraft.client.main.Main\",\"libraries\":[]}", "version.json", at: paths.instance(original.id))
        try write("native bytes", "natives/fixture.dylib", at: paths.instance(original.id))
        try write("installation history", "installer.log", at: paths.instance(original.id))
        try write("runtime history", "sessions/old/launcher.log", at: paths.instance(original.id))
        try write("options", "options.txt", at: paths.game(original.id))
        try write("config", "config/custom.json", at: paths.game(original.id))
        try write("old logs", "logs/latest.log", at: paths.game(original.id))
        let source = paths.cache.appendingPathComponent("mod.jar"); try Data("mod".utf8).write(to: source)
        let mod = ManagedContent(projectID: "fixture", versionID: "one", title: "Fixture", versionName: "1", kind: .mod, filename: "mod.jar", size: 3, requiredProjects: [])
        try await ContentManager(paths: paths, instanceID: original.id).install([.init(record: mod, source: source)])
        let world = paths.game(original.id).appendingPathComponent("saves/World")
        try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
        try WorldTests().nbt().write(to: world.appendingPathComponent("level.dat"))
        _ = try await WorldManager(paths: paths, instanceID: original.id).backup(folder: "World")
        return (paths, original, collection)
    }

    @Test func duplicatesInstallationAndSettingsWithIndependentDataAndFreshHistory() async throws {
        let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let pack = InstalledModpack(format: "Modrinth", name: "Fixture pack", version: "1", origin: .init(provider: .modrinth, projectID: "project", versionID: "version"), settings: source, files: [])
        try ModpackRegistry.save(pack, paths: paths, instanceID: source.id)
        let service = InstanceCopier(paths: paths)
        let preview = try await service.preview(instanceID: source.id, name: "  Independent copy  ", directoryID: target.id, options: .init(includeBackups: true))
        #expect(preview.copy.id != source.id && preview.copy.name == "Independent copy" && preview.copy.directoryID == target.id)
        #expect(preview.bytes > 0 && !FileManager.default.fileExists(atPath: preview.destination.path))
        try StateStore.update(paths) { $0.settings.defaultMemoryMB = 6144 }
        let result = try await service.copy(preview), copy = try #require(result.state.instances.first { $0.id == preview.copy.id }), current = paths.configured(with: result.state)
        #expect(copy.installed && copy.runDirectory == .isolated && copy.customRunDirectory == nil)
        #expect(copy.playTime == 0 && copy.lastPlayed == nil && !copy.favorite)
        #expect(copy.launchOverrides == source.launchOverrides && copy.extraJVMArguments == source.extraJVMArguments)
        #expect(copy.resolvedLaunchSettings(defaults: result.state.settings).memory.maximumMB == 6144)
        #expect(try Data(contentsOf: current.manifest(copy.id)) == Data(contentsOf: paths.manifest(source.id)))
        #expect(try String(contentsOf: current.instance(copy.id).appendingPathComponent("natives/fixture.dylib"), encoding: .utf8) == "native bytes")
        #expect(!FileManager.default.fileExists(atPath: current.instance(copy.id).appendingPathComponent("sessions").path))
        #expect(!FileManager.default.fileExists(atPath: current.instance(copy.id).appendingPathComponent("installer.log").path))
        #expect(!FileManager.default.fileExists(atPath: current.game(copy.id).appendingPathComponent("logs").path))
        #expect(try await ContentManager(paths: current, instanceID: copy.id).records().first?.projectID == "fixture")
        #expect(try await WorldManager(paths: current, instanceID: copy.id).backups().count == 1)
        let copiedPack = try #require(try ModpackRegistry.load(paths: current, instanceID: copy.id))
        #expect(copiedPack.settings.id == copy.id && copiedPack.settings.directoryID == target.id && copiedPack.origin == pack.origin)
        try Data("changed copy".utf8).write(to: current.game(copy.id).appendingPathComponent("mods/mod.jar"))
        #expect(try String(contentsOf: paths.game(source.id).appendingPathComponent("mods/mod.jar"), encoding: .utf8) == "mod")
        #expect(!InstanceCopyGuard.hasPending(paths: current, instanceID: source.id) && !InstanceCopyGuard.hasPending(paths: current, instanceID: copy.id))
        #expect(result.preservedCopy == nil && result.warning == nil)
    }

    @Test func sharedAndCustomSourcesBecomeIndependentAndWorldOptionsAreRespected() async throws {
        for mode in [GameRunDirectory.shared, .custom] {
            let (paths, source, _) = try await fixture(mode: mode); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let service = InstanceCopier(paths: paths)
            let preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: GameDirectory.defaultID, options: .init(includeWorlds: false))
            let result = try await service.copy(preview), current = paths.configured(with: result.state)
            #expect(current.game(source.id) != current.game(preview.copy.id))
            #expect(preview.copy.runDirectory == .isolated && preview.copy.customRunDirectory == nil)
            #expect(!FileManager.default.fileExists(atPath: current.game(preview.copy.id).appendingPathComponent("saves").path))
            #expect(try await WorldManager(paths: current, instanceID: preview.copy.id).backups().isEmpty)
            #expect(try await ContentManager(paths: current, instanceID: preview.copy.id).records().count == 1)
            #expect(FileManager.default.fileExists(atPath: paths.game(source.id).appendingPathComponent("saves/World/level.dat").path))
        }
    }

    @Test func rejectsActiveSourcesChangedPreviewsAndMissingInstalledManifests() async throws {
        let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let service = InstanceCopier(paths: paths)
        var lease: GameRunLease? = try GameRunLease.acquire(paths: paths, instanceID: source.id)
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id) }
        withExtendedLifetime(lease) {}; lease = nil
        let preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
        try StateStore.update(paths) { $0.instances[0].extraJVMArguments = "-Dchanged=true" }
        await #expect(throws: (any Error).self) { try await service.copy(preview) }
        let fresh = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
        try Data("changed source".utf8).write(to: paths.game(source.id).appendingPathComponent("options.txt"))
        await #expect(throws: (any Error).self) { try await service.copy(fresh) }
        try FileManager.default.removeItem(at: paths.manifest(source.id))
        await #expect(throws: (any Error).self) { try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id) }
        #expect(try StateStore.load(paths).instances.count == 1)
    }

    @Test func cancellationAndForeignDestinationPreserveSourceAndDoNotRegisterPartialInstances() async throws {
        for foreign in [false, true] {
            let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let service = InstanceCopier(paths: paths), preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
            let operation = Task {
                try await service.copy(preview) { progress in
                    if foreign && progress.phase == .publishing && progress.completed == 0 {
                        do { try FileManager.default.createDirectory(at: preview.destination, withIntermediateDirectories: true); try Data("foreign".utf8).write(to: preview.destination.appendingPathComponent("user.txt")) }
                        catch { Issue.record(error) }
                    } else if !foreign && progress.phase == .publishing && progress.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            do { _ = try await operation.value; Issue.record("Expected an interrupted copy") }
            catch let failure as RunDirectoryCopyFailure {
                let workspace = try #require(failure.preservedCopy)
                #expect(workspace.path.hasPrefix(target.url.path))
                #expect(InstanceCopyGuard.preservedWorkspaces(paths: paths, sourceID: source.id) == [workspace])
            }
            #expect(try StateStore.load(paths).instances == [source])
            #expect(try String(contentsOf: paths.game(source.id).appendingPathComponent("options.txt"), encoding: .utf8) == "options")
            if foreign { #expect(try String(contentsOf: preview.destination.appendingPathComponent("user.txt"), encoding: .utf8) == "foreign") }
            else { #expect(!FileManager.default.fileExists(atPath: preview.destination.path)) }
            #expect(!InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
        }
    }

    @Test func recoveryDistinguishesAnUnpublishedCopyFromTheAtomicRegistrationReceipt() async throws {
        for committed in [false, true] {
            let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let service = InstanceCopier(paths: paths), preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
            var journal = InstanceCopyJournal(id: preview.id, original: source, copy: preview.copy, targetCollection: target, createdAt: Date(), phase: .publishing)
            journal.version = 1 // Recovery remains compatible with pre-verification journals.
            let root = try InstanceCopyJournal.root(paths: paths, sourceID: source.id), incoming = try journal.incoming(paths: paths)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: incoming.appendingPathComponent("minecraft"), withIntermediateDirectories: true)
            try Data("copy data".utf8).write(to: incoming.appendingPathComponent("minecraft/options.txt"))
            try InstanceCopyGuard.mark(journal, at: incoming); journal.stagedIdentity = try .read(incoming); try journal.save(paths: paths)
            try RunDirectoryFileCopy.moveWithoutReplacing(incoming, to: journal.destination(paths: paths))
            if committed { try StateStore.update(paths) { $0.instances.append(preview.copy) } }
            #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths, instanceID: source.id) }
            await #expect(throws: (any Error).self) { try await ContentManager(paths: paths, instanceID: source.id).records() }
            #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths.including(preview.copy), instanceID: preview.copy.id) }
            #expect(throws: (any Error).self) { try GameDirectoryStore.relocate(target.id, to: target.url, paths: paths) }
            #expect(try await service.pending(instanceID: committed ? preview.copy.id : source.id)?.committed == committed)
            if committed {
                let moved = target.url.appendingPathComponent("Moved completed copy")
                try FileManager.default.moveItem(at: preview.destination, to: moved)
                await #expect(throws: (any Error).self) { try await service.recover(sourceID: source.id, transactionID: journal.id) }
                #expect(InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
                #expect(FileManager.default.fileExists(atPath: root.path))
                try FileManager.default.moveItem(at: moved, to: preview.destination)
            }
            let result = try await service.recover(sourceID: source.id, transactionID: journal.id)
            #expect(result.state.instances.count == (committed ? 2 : 1))
            #expect((result.preservedCopy == nil) == committed)
            if committed { #expect(try String(contentsOf: preview.destination.appendingPathComponent("minecraft/options.txt"), encoding: .utf8) == "copy data") }
            else { #expect(!FileManager.default.fileExists(atPath: preview.destination.path)) }
            #expect(!InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
        }
    }

    @Test func recoveryRetainsCompleteStagingWhenPortablePublicationStopsAfterClaimingItsRoot() async throws {
        enum Interruption: Error { case simulated }
        let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let service = InstanceCopier(paths: paths), preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
        var journal = InstanceCopyJournal(id: preview.id, original: source, copy: preview.copy, targetCollection: target, createdAt: Date(), phase: .publishing)
        journal.version = 1
        let root = try InstanceCopyJournal.root(paths: paths, sourceID: source.id), incoming = try journal.incoming(paths: paths)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try Data("complete data".utf8).write(to: incoming.appendingPathComponent("file.txt"))
        try InstanceCopyGuard.mark(journal, at: incoming); journal.stagedIdentity = try .read(incoming); try journal.save(paths: paths)
        #expect(throws: Interruption.simulated) {
            try RunDirectoryFileCopy.copyForPublication(incoming, to: preview.destination, directory: true, excluding: [InstanceCopyGuard.markerName]) { identity in
                journal.publishedIdentity = identity; try journal.save(paths: paths)
                try InstanceCopyGuard.mark(journal, at: preview.destination); throw Interruption.simulated
            } validate: {} progress: { _ in }
        }
        let result = try await service.recover(sourceID: source.id, transactionID: journal.id)
        #expect(result.warning == nil && result.preservedCopy != nil)
        #expect(try String(contentsOf: incoming.appendingPathComponent("file.txt"), encoding: .utf8) == "complete data")
        #expect(!FileManager.default.fileExists(atPath: preview.destination.path))
    }

    @Test func oversizedUnicodeNamesCannotCreateAnUnreadableCopyReservation() async throws {
        let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        // Grapheme count alone does not bound the encoded marker size.
        let name = "e" + String(repeating: "\u{0301}", count: 5000)
        #expect(name.count == 1)
        try StateStore.update(paths) { $0.instances[0].name = name }
        await #expect(throws: (any Error).self) { try await InstanceCopier(paths: paths).preview(instanceID: source.id, name: "Copy", directoryID: target.id) }
        #expect(!InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
        #expect(try StateStore.load(paths).instances.count == 1)
        #expect(try String(contentsOf: paths.game(source.id).appendingPathComponent("options.txt"), encoding: .utf8) == "options")
    }
    @Test func equalSizeSourceEditsCannotBypassPreviewOrPublicationChecks() async throws {
        for afterPublication in [false, true] {
            let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let service = InstanceCopier(paths: paths), preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
            let file = paths.game(source.id).appendingPathComponent("options.txt")
            let date = try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            @Sendable func edit() throws {
                let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
                try handle.write(contentsOf: Data("changed".utf8)); try handle.synchronize()
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
            }
            if !afterPublication { try edit() }
            await #expect(throws: (any Error).self) {
                _ = try await service.copy(preview) { progress in
                    if afterPublication && progress.phase == .publishing && progress.completed == 1 {
                        do { try edit() } catch { Issue.record(error) }
                    }
                }
            }
            #expect(try StateStore.load(paths).instances == [source])
            #expect(!InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
            #expect(try String(contentsOf: file, encoding: .utf8) == "changed")
        }
    }

    @Test func committedCopiesKeepRecoveryDataUntilContentAndReceiptAreRestored() async throws {
        for damage in ["content", "record", "missing-record", "nonempty-lock"] {
            let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let service = InstanceCopier(paths: paths), preview = try await service.preview(instanceID: source.id, name: "Copy", directoryID: target.id)
            let root = try InstanceCopyJournal.root(paths: paths, sourceID: source.id)
            let record = root.appendingPathComponent("verification.json"), backup = paths.cache.appendingPathComponent("receipt-backup.json")
            let file = preview.destination.appendingPathComponent("minecraft/options.txt")
            let result = try await service.copy(preview) { progress in
                if progress.phase == .committed {
                    do {
                        try FileManager.default.copyItem(at: record, to: backup)
                        if damage == "content" { try Data("changed".utf8).write(to: file) }
                        else if damage == "record" { try Data("{}".utf8).write(to: record) }
                        else if damage == "nonempty-lock" { try Data("keep data".utf8).write(to: preview.destination.appendingPathComponent(".content-operation.lock")) }
                        else { try FileManager.default.removeItem(at: record) }
                    } catch { Issue.record(error) }
                }
            }
            #expect(result.state.instances.count == 2 && result.warning != nil)
            #expect(InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
            await #expect(throws: (any Error).self) { try await service.recover(sourceID: source.id, transactionID: preview.id) }
            #expect(FileManager.default.fileExists(atPath: root.path))
            if damage == "content" { try Data("options".utf8).write(to: file) }
            else if damage == "nonempty-lock" { try Data().write(to: preview.destination.appendingPathComponent(".content-operation.lock")) }
            else { try Data(contentsOf: backup).write(to: record, options: .atomic) }
            // A legacy client may have created these before its pending check.
            for lock in [".ruri-game.lock", ".content-operation.lock", ".world-operation.lock"] { try Data().write(to: preview.destination.appendingPathComponent(lock)) }
            let recovered = try await service.recover(sourceID: source.id, transactionID: preview.id)
            #expect(recovered.warning == nil && recovered.preservedCopy == nil)
            #expect(!InstanceCopyGuard.hasPending(paths: paths, instanceID: source.id))
        }
    }

    @Test func newPublicationJournalsRequireContentReceiptsAndPendingTargetsAreNotPrepared() async throws {
        let (paths, source, target) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let preview = try await InstanceCopier(paths: paths).preview(instanceID: source.id, name: "Copy", directoryID: target.id)
        var journal = InstanceCopyJournal(id: preview.id, original: source, copy: preview.copy, targetCollection: target, createdAt: Date(), phase: .publishing)
        #expect(throws: (any Error).self) { try journal.validate() }
        journal.phase = .copying
        let root = try InstanceCopyJournal.root(paths: paths, sourceID: source.id)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try journal.save(paths: paths)
        try FileManager.default.createDirectory(at: preview.destination, withIntermediateDirectories: true)
        try InstanceCopyGuard.mark(journal, at: preview.destination)
        let before = try FileTreeManifest.capture(in: preview.destination)
        #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths.including(preview.copy), instanceID: preview.copy.id) }
        await #expect(throws: (any Error).self) { try await ContentManager(paths: paths.including(preview.copy), instanceID: preview.copy.id).records() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths.including(preview.copy), instanceID: preview.copy.id).worlds() }
        await #expect(throws: (any Error).self) { try await WorldManager(paths: paths.including(preview.copy), instanceID: preview.copy.id).backups() }
        try before.requireMatch(in: preview.destination)
    }
}
