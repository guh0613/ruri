import Foundation
import Testing
@testable import RuriCore

struct CustomRunDirectoryChangeTests {
    @Test func recoveryIdentitySurvivesChangedMountDeviceButRejectsOtherVolumesAndReplacements() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-volume-identity-\(UUID())")
        try Data("owned copy".utf8).write(to: file); defer { try? FileManager.default.removeItem(at: file) }
        let identity = try RunDirectoryCopyJournal.Identity.read(file)
        let volume = try #require(identity.volumeUUID)
        let remounted = RunDirectoryCopyJournal.Identity(device: identity.device + 1, inode: identity.inode, directory: false, volumeUUID: volume)
        #expect(remounted.matches(file))
        var otherVolume = remounted; otherVolume.volumeUUID = UUID().uuidString
        #expect(!otherVolume.matches(file))
        let legacy = RunDirectoryCopyJournal.Identity(device: identity.device, inode: identity.inode, directory: false)
        #expect(legacy.matches(file))
        let legacyWrongDevice = RunDirectoryCopyJournal.Identity(device: identity.device + 1, inode: identity.inode, directory: false)
        #expect(!legacyWrongDevice.matches(file))
        try Data("replacement".utf8).write(to: file, options: .atomic)
        #expect(!identity.matches(file))
    }

    private func fixture(withContent: Bool = false) async throws -> (LauncherPaths, GameInstance, CustomRunDirectory) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-custom-change-\(UUID())")
        let base = LauncherPaths(root: root.appendingPathComponent("data")), target = root.appendingPathComponent("Selected game")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let custom = try CustomRunDirectory.register(at: target, paths: base)
        let instance = GameInstance(name: "Directory switch", gameVersion: "1.21.1")
        var state = PersistentState(); state.instances = [instance]; try StateStore.save(state, to: base)
        let paths = base.configured(with: state)
        try FileManager.default.createDirectory(at: paths.game(instance.id), withIntermediateDirectories: true)
        try Data("original".utf8).write(to: paths.game(instance.id).appendingPathComponent("options.txt"))
        if withContent {
            let file = paths.cache.appendingPathComponent("mod.jar"); try Data("mod".utf8).write(to: file)
            let record = ManagedContent(projectID: "fixture", versionID: "one", title: "Fixture", versionName: "1", kind: .mod, filename: "mod.jar", size: 3, requiredProjects: [])
            try await ContentManager(paths: paths, instanceID: instance.id).install([.init(record: record, source: file)])
        }
        return (paths, instance, custom)
    }

    private func stagedJournal(paths: LauncherPaths, instance: GameInstance, custom: CustomRunDirectory, name: String, bytes: Data, directory: Bool = false) throws -> (RunDirectoryCopyJournal, URL, URL) {
        var journal = RunDirectoryCopyJournal(id: UUID(), original: instance, target: .custom, createdAt: Date(), phase: .publishing, items: [], emptyDirectories: [])
        journal.targetCustomDirectory = custom; journal.stagingOnTarget = true
        let record = try RunDirectoryCopyJournal.root(paths: paths, instanceID: instance.id)
        let workspace = try journal.workspace(paths: paths)
        try FileManager.default.createDirectory(at: record, withIntermediateDirectories: true)
        let staged = workspace.appendingPathComponent("incoming/game/" + name)
        try FileManager.default.createDirectory(at: directory ? staged : staged.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = directory ? staged.appendingPathComponent("large.bin") : staged
        try bytes.write(to: file)
        journal.items = [.init(area: .game, name: name, identity: try .read(staged))]
        try journal.save(paths: paths)
        return (journal, workspace, staged)
    }

    @Test func existingCustomTargetsCanBeChangedAndSwitchedBackWithoutMovingFiles() async throws {
        let (paths, instance, custom) = try await fixture(withContent: true); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        try Data("target-one".utf8).write(to: custom.url.appendingPathComponent("options.txt"))
        let service = GameRunDirectoryChange(paths: paths)
        let preview = try await service.preview(instanceID: instance.id, target: .custom, customDirectory: custom)
        #expect(!preview.canCopyToTarget)
        let state = try await service.useExisting(preview)
        #expect(state.instances[0].customRunDirectory?.id == custom.id && state.instances[0].runDirectory == .custom)
        #expect(try String(contentsOf: paths.game(instance.id).appendingPathComponent("options.txt"), encoding: .utf8) == "original")
        let otherURL = custom.url.deletingLastPathComponent().appendingPathComponent("Another game")
        try FileManager.default.createDirectory(at: otherURL, withIntermediateDirectories: false)
        let other = try CustomRunDirectory.register(at: otherURL, paths: paths.configured(with: state))
        let changed = try await service.useExisting(service.preview(instanceID: instance.id, target: .custom, customDirectory: other))
        #expect(changed.instances[0].customRunDirectory?.id == other.id)
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "target-one")
        let restored = try await service.useExisting(service.preview(instanceID: instance.id, target: .isolated))
        #expect(restored.instances[0].runDirectory == .isolated && restored.instances[0].customRunDirectory?.id == other.id)
        #expect(try await ContentManager(paths: paths.configured(with: restored), instanceID: instance.id).records().first?.projectID == "fixture")
    }

    @Test func copiesBetweenCustomRootsWithoutChangingTheOriginalData() async throws {
        let (paths, instance, custom) = try await fixture(withContent: true); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let service = GameRunDirectoryChange(paths: paths)
        let preview = try await service.preview(instanceID: instance.id, target: .custom, customDirectory: custom)
        let result = try await service.copyToEmpty(preview)
        let current = paths.configured(with: result.state)
        #expect(current.game(instance.id) == custom.url)
        #expect(try await ContentManager(paths: current, instanceID: instance.id).records().first?.projectID == "fixture")
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "original")
        try Data("changed-copy".utf8).write(to: custom.url.appendingPathComponent("options.txt"))
        #expect(try String(contentsOf: paths.game(instance.id).appendingPathComponent("options.txt"), encoding: .utf8) == "original")
        try custom.validateAvailability()
        #expect(!RunDirectoryCopyGuard.hasPending(paths: current, instanceID: instance.id))
        let anotherURL = custom.url.deletingLastPathComponent().appendingPathComponent("Another empty target")
        try FileManager.default.createDirectory(at: anotherURL, withIntermediateDirectories: false)
        let another = try CustomRunDirectory.register(at: anotherURL, paths: current)
        let second = try await service.copyToEmpty(service.preview(instanceID: instance.id, target: .custom, customDirectory: another))
        #expect(second.state.instances[0].customRunDirectory?.id == another.id)
        #expect(try String(contentsOf: another.url.appendingPathComponent("options.txt"), encoding: .utf8) == "changed-copy")
        #expect(try String(contentsOf: custom.url.appendingPathComponent("options.txt"), encoding: .utf8) == "changed-copy")
    }

    @Test func cancellationRetainsTheTargetVolumeWorkspaceAndMakesItDiscoverable() async throws {
        let (paths, instance, custom) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let service = GameRunDirectoryChange(paths: paths)
        let preview = try await service.preview(instanceID: instance.id, target: .custom, customDirectory: custom)
        let work = Task {
            try await service.copyToEmpty(preview) { progress in
                if progress.phase == .publishing && progress.completed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await work.value; Issue.record("Expected cancellation") }
        catch let failure as RunDirectoryCopyFailure {
            let workspace = try #require(failure.preservedCopy)
            #expect(workspace.path.hasPrefix(custom.url.path + "/.ruri/"))
            #expect(try String(contentsOf: workspace.appendingPathComponent("incoming/game/options.txt"), encoding: .utf8) == "original")
            #expect(RunDirectoryCopyGuard.preservedWorkspaces(paths: paths, instanceID: instance.id) == [workspace])
        }
        #expect(try StateStore.load(paths).instances[0].runDirectory == nil)
        #expect(try FileTree.entries(in: custom.url, excluding: [".ruri"]).isEmpty)
        #expect(!RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: instance.id))
    }

    @Test func journalRecoveryHandlesTargetStagingBeforeAndAfterStateCommit() async throws {
        for committed in [false, true] {
            let (paths, instance, custom) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let (journal, workspace, staged) = try stagedJournal(paths: paths, instance: instance, custom: custom, name: "copied.txt", bytes: Data("copied".utf8))
            let targetPaths = journal.targetPaths(paths)
            try RunDirectoryCopyGuard.mark(journal, paths: targetPaths)
            try RunDirectoryFileCopy.moveWithoutReplacing(staged, to: custom.url.appendingPathComponent("copied.txt"))
            if committed {
                try StateStore.update(paths) { $0.instances[0].runDirectory = .custom; $0.instances[0].customRunDirectory = custom; $0.instances[0].lastRunDirectoryChangeID = journal.id }
            }
            var other = GameInstance(name: "Other custom instance", gameVersion: "1.21.1"); other.runDirectory = .custom; other.customRunDirectory = custom
            #expect(throws: (any Error).self) { try GameRunLease.acquire(paths: paths.including(other), instanceID: other.id) }
            let result = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: instance.id, transactionID: journal.id)
            if committed {
                #expect(result.preservedCopy == nil)
                #expect(try String(contentsOf: custom.url.appendingPathComponent("copied.txt"), encoding: .utf8) == "copied")
                #expect(!FileManager.default.fileExists(atPath: workspace.path))
            } else {
                #expect(try #require(result.preservedCopy).path == workspace.path)
                #expect(try String(contentsOf: workspace.appendingPathComponent("incoming/game/copied.txt"), encoding: .utf8) == "copied")
                #expect(!FileManager.default.fileExists(atPath: custom.url.appendingPathComponent("copied.txt").path))
            }
            #expect(!RunDirectoryCopyGuard.hasPending(paths: paths.configured(with: result.state), instanceID: instance.id))
        }
    }

    @Test func portablePublicationNeverReplacesExistingFilesOrDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-portable-publish-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
        for directory in [false, true] {
            let source = root.appendingPathComponent("source-\(directory)"), target = root.appendingPathComponent("target-\(directory)")
            if directory { try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false); try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false) }
            let sourceFile = directory ? source.appendingPathComponent("file.txt") : source
            let targetFile = directory ? target.appendingPathComponent("file.txt") : target
            try Data("staged".utf8).write(to: sourceFile); try Data("foreign".utf8).write(to: targetFile)
            #expect(throws: (any Error).self) {
                try RunDirectoryFileCopy.copyForPublication(source, to: target, directory: directory, created: { _ in Issue.record("Must not claim an existing destination") }, validate: {}, progress: { _ in })
            }
            #expect(try String(contentsOf: sourceFile, encoding: .utf8) == "staged")
            #expect(try String(contentsOf: targetFile, encoding: .utf8) == "foreign")
        }
    }

    @Test func recoveryPreservesStagingAndReturnsPartialPortablePublicationsIncludingLaterEdits() async throws {
        enum Interruption: Error { case simulated }
        for directory in [false, true] {
            let (paths, instance, custom) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
            let bytes = Data(repeating: 90, count: 4_194_304)
            let (initialJournal, workspace, staged) = try stagedJournal(paths: paths, instance: instance, custom: custom, name: "copied", bytes: bytes, directory: directory)
            var journal = initialJournal
            let stagedFile = directory ? staged.appendingPathComponent("large.bin") : staged
            let target = custom.url.appendingPathComponent("copied"), targetPaths = journal.targetPaths(paths)
            try RunDirectoryCopyGuard.mark(journal, paths: targetPaths)
            var written: Int64 = 0
            do {
                try RunDirectoryFileCopy.copyForPublication(staged, to: target, directory: directory) { identity in
                    journal.items[0].publishedIdentity = identity; try journal.save(paths: paths)
                } validate: {
                    if !directory && written > 0 { throw Interruption.simulated }
                } progress: { written += $0 }
                #expect(directory)
            } catch Interruption.simulated { #expect(!directory && written > 0 && written < bytes.count) }
            if directory { try Data("later edit".utf8).write(to: target.appendingPathComponent("user.txt")) }
            let result = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: instance.id, transactionID: journal.id)
            #expect(result.warning == nil)
            #expect(try Data(contentsOf: stagedFile) == bytes)
            #expect(!FileManager.default.fileExists(atPath: target.path))
            let returns = try FileManager.default.contentsOfDirectory(at: workspace.appendingPathComponent("returned"), includingPropertiesForKeys: nil)
            let returned = try #require(returns.first).appendingPathComponent("copied")
            if directory {
                #expect(try Data(contentsOf: returned.appendingPathComponent("large.bin")) == bytes)
                #expect(try String(contentsOf: returned.appendingPathComponent("user.txt"), encoding: .utf8) == "later edit")
            } else { #expect(try Data(contentsOf: returned).count == written) }
            #expect(!RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: instance.id))
        }
    }

    @Test func failureBeforeSavingPublicationIdentityPreservesUnknownPlaceholderAndReportsIt() async throws {
        enum Interruption: Error { case simulated }
        let (paths, instance, custom) = try await fixture(); defer { try? FileManager.default.removeItem(at: paths.root.deletingLastPathComponent()) }
        let (journal, _, staged) = try stagedJournal(paths: paths, instance: instance, custom: custom, name: "copied.txt", bytes: Data("staged".utf8))
        let target = custom.url.appendingPathComponent("copied.txt")
        #expect(throws: Interruption.simulated) {
            try RunDirectoryFileCopy.copyForPublication(staged, to: target, directory: false, created: { _ in throw Interruption.simulated }, validate: {}, progress: { _ in Issue.record("No data should be written before the identity is durable") })
        }
        let placeholder = try Data(contentsOf: target)
        let result = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: instance.id, transactionID: journal.id)
        #expect(result.warning?.contains("copied.txt") == true)
        #expect(try Data(contentsOf: target) == placeholder)
        #expect(try String(contentsOf: staged, encoding: .utf8) == "staged")
    }
}
