import RuriLocalization
import Foundation
import Darwin

extension InstanceMover {
    public func move(_ preview: InstanceMovePreview, progress: @Sendable (InstanceMoveProgress) -> Void = { _ in }) async throws -> InstanceMoveResult {
        if preview.repository != nil { return try await moveRepository(preview, progress: progress) }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard state.instances.first(where: { $0.id == preview.source.id }) == preview.source else { throw RuriError.message(Messages.CoreInstanceMover.settingsChangedAfterPreview) }
        let access = try await InstanceMoveAccess.acquire(instance: preview.source, paths: current)
        defer { withExtendedLifetime(access) {} }
        progress(.init(phase: .verifying))
        try validate(preview, state: state)
        let root = try InstanceMoveJournal.root(paths: current, instanceID: preview.source.id)
        let preparing = root.deletingLastPathComponent().appendingPathComponent(".preparing-\(preview.id.uuidString)")
        var journal: InstanceMoveJournal?
        var activated = false
        do {
            try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: preparing, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let digest = try preview.snapshot.original.save(to: preparing.appendingPathComponent("source.json"))
            journal = InstanceMoveJournal(id: preview.id, original: preview.source, moved: preview.moved,
                                          sourceCollection: preview.sourceCollection, targetCollection: preview.targetCollection,
                                          createdAt: Date(), sourceIdentity: preview.sourceIdentity, sourceDigest: digest)
            var record = journal!
            try StateStore.update(paths) { latest in try validateBinding(record, in: latest) }
            try record.save(paths: current, at: preparing)
            try RunDirectoryFileCopy.moveWithoutReplacing(preparing, to: root); activated = true
            let workspace = try record.workspace(paths: current), incoming = try record.incoming(paths: current)
            try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard mkdir(workspace.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreInstanceMover.workspaceCreateFailed) }
            record.workspaceIdentity = try .read(workspace); try record.save(paths: current); journal = record
            let location = record
            func checkLocations() throws {
                try location.validateLocations(paths: current)
                guard location.sourceIdentity.matches(preview.sourceDirectory), location.workspaceIdentity?.matches(workspace) == true else { throw RuriError.message(Messages.CoreInstanceMover.sourceOrWorkspaceIdentityChanged) }
            }
            var copied: Int64 = 0, lastProgress = Date.distantPast
            progress(.init(phase: .copying, totalBytes: preview.bytes))
            try RunDirectoryFileCopy.entries(preview.snapshot.entries, to: incoming, validate: checkLocations) { amount, _ in
                copied += amount
                if copied == preview.bytes || Date().timeIntervalSince(lastProgress) >= 0.1 {
                    lastProgress = Date(); progress(.init(phase: .copying, bytesCopied: copied, totalBytes: preview.bytes))
                }
            }
            if preview.source.runDirectory == .shared { try FileManager.default.createDirectory(at: incoming.appendingPathComponent("minecraft"), withIntermediateDirectories: true) }
            try FileExtendedAttributes.copy(from: preview.sourceDirectory, to: incoming)
            progress(.init(phase: .verifying))
            try preview.snapshot.destination.requireMatch(in: incoming)
            try rebindModpack(incoming, moved: preview.moved)
            try preview.snapshot.requireUnchanged(instance: preview.source, paths: current, transactionID: preview.id)
            let destinationManifest = try FileTreeManifest.capture(in: incoming)
            record.destinationDigest = try destinationManifest.save(to: root.appendingPathComponent("destination.json"))
            record.stagedIdentity = try .read(incoming); record.phase = .publishing
            try record.save(paths: current); journal = record
            let destination = try record.destination(paths: current)
            var published: Int64 = 0
            progress(.init(phase: .publishing, totalBytes: preview.bytes))
            try RunDirectoryFileCopy.publish(incoming, to: destination, directory: true, ignoringTransientFiles: false) { identity in
                record.publishedIdentity = identity; try record.save(paths: current); journal = record
            } validate: { try checkLocations() } progress: { amount in
                published += amount
                progress(.init(phase: .publishing, bytesCopied: published, totalBytes: preview.bytes))
            }
            try Task.checkCancellation()
            progress(.init(phase: .verifying))
            try preview.snapshot.requireUnchanged(instance: preview.source, paths: current, transactionID: preview.id)
            try verifyDestination(record, manifest: destinationManifest, paths: current)
            try access.lease.clearFinishedReservation(paths: current, instanceID: preview.source.id)
            let saved = try StateStore.update(paths) { latest in
                try validateBinding(record, in: latest)
                guard let index = latest.instances.firstIndex(where: { $0.id == record.original.id }) else { throw RuriError.message(Messages.CoreInstanceMover.instanceRemoved) }
                latest.instances[index] = record.moved
                latest.selectedInstanceID = record.moved.id; latest.selectedDirectoryID = record.moved.directoryID
            }
            progress(.init(phase: .committed))
            record.phase = .committed; try record.save(paths: current); journal = record
            return try finish(record, state: saved, preservingSource: false, progress: progress)
        } catch {
            guard activated, let journal else { try? FileManager.default.removeItem(at: preparing); throw error }
            let reason = error.localizedDescription
            let latest: PersistentState
            do { latest = try StateStore.load(paths) }
            catch { throw InstanceMoveFailure(message: Messages.CoreInstanceMover.moveCommitUnknown(error.localizedDescription).localized, preservedFiles: [root], cancelled: Task.isCancelled) }
            if try journal.isCommitted(in: latest) {
                return .init(state: latest, preservedFiles: [root], warning: Messages.CoreInstanceMover.moveCommitted(String(describing: reason)).localized)
            }
            do {
                let preserved = try abandon(journal, paths: paths.configured(with: latest))
                throw InstanceMoveFailure(message: Task.isCancelled || error is CancellationError ? Messages.CoreInstanceMover.moveCancelled.localized : Messages.CoreInstanceMover.moveIncomplete(String(describing: reason)).localized, preservedFiles: preserved, cancelled: Task.isCancelled || error is CancellationError)
            } catch let failure as InstanceMoveFailure { throw failure }
            catch { throw InstanceMoveFailure(message: Messages.CoreInstanceMover.moveFailed(String(describing: reason), error.localizedDescription).localized, preservedFiles: [root], cancelled: Task.isCancelled) }
        }
    }

    public func pending(instanceID: UUID) throws -> InstanceMoveRecovery? {
        guard InstanceMoveGuard.hasPending(paths: paths, instanceID: instanceID) else { return nil }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        if RepositoryMoveJournal.exists(paths: current, instanceID: instanceID) { return try repositoryPending(instanceID, state: state) }
        let record = try InstanceMoveJournal.load(paths: current, instanceID: instanceID)
        return .init(id: record.id, instance: record.original, source: try record.source(paths: current),
                     destination: try record.destination(paths: current), workspace: try record.workspace(paths: current),
                     retiredSource: try record.retiredSource(paths: current), committed: try record.isCommitted(in: state))
    }

    public func recover(instanceID: UUID, transactionID: UUID, preservingSource: Bool = false, progress: @Sendable (InstanceMoveProgress) -> Void = { _ in }) throws -> InstanceMoveResult {
        let lease = try InstanceLocationLease.acquireForMoveRecovery(paths: paths, instanceID: instanceID)
        defer { withExtendedLifetime(lease) {} }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        if RepositoryMoveJournal.exists(paths: current, instanceID: instanceID) {
            return try recoverRepository(instanceID, transactionID: transactionID, state: state, preservingSource: preservingSource, progress: progress)
        }
        let record = try InstanceMoveJournal.load(paths: current, instanceID: instanceID)
        guard record.id == transactionID else { throw RuriError.message(Messages.CoreInstanceMover.recoveryRecordChanged) }
        try record.validateLocations(paths: current)
        if try record.isCommitted(in: state) { return try finish(record, state: state, preservingSource: preservingSource, progress: progress) }
        return .init(state: state, preservedFiles: try abandon(record, paths: current), warning: Messages.CoreInstanceMover.moveRecovered.localized)
    }

    private func validateBinding(_ record: InstanceMoveJournal, in state: PersistentState) throws {
        guard state.instances.first(where: { $0.id == record.original.id }) == record.original else { throw RuriError.message(Messages.CoreInstanceMover.settingsChangedAfterPreview) }
        try record.validateLocations(paths: paths.configured(with: state))
    }
    private func rebindModpack(_ root: URL, moved: GameInstance) throws {
        let file = root.appendingPathComponent("modpack-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var record = try ModpackRegistry.read(file, game: root.appendingPathComponent("minecraft"))
        record.settings.id = moved.id; record.settings.directoryID = moved.directoryID
        record.settings.runDirectory = moved.runDirectory; record.settings.customRunDirectory = moved.customRunDirectory
        record.settings.lastRunDirectoryChangeID = nil; record.settings.lastInstanceCopyID = nil; record.settings.lastInstanceMoveID = nil
        try FileExtendedAttributes.rewrite(JSONEncoder().encode(record), at: file)
    }
    private func verifyDestination(_ record: InstanceMoveJournal, manifest: FileTreeManifest, paths: LauncherPaths) throws {
        let destination = try record.destination(paths: paths)
        guard (record.publishedIdentity ?? record.stagedIdentity)?.matches(destination) == true else { throw RuriError.message(Messages.CoreInstanceMover.destinationIdentityChanged) }
        try manifest.requireMatch(in: destination)
    }

    private func finish(_ input: InstanceMoveJournal, state: PersistentState, preservingSource: Bool, progress: @Sendable (InstanceMoveProgress) -> Void) throws -> InstanceMoveResult {
        let current = paths.configured(with: state)
        var record = input
        try record.validateLocations(paths: current)
        guard try record.isCommitted(in: state), let digest = record.destinationDigest else { throw RuriError.message(Messages.CoreInstanceMover.uncommittedMove) }
        let root = try InstanceMoveJournal.root(paths: current, instanceID: record.original.id)
        progress(.init(phase: .verifying))
        let destinationManifest = try FileTreeManifest.load(from: root.appendingPathComponent("destination.json"), expectedDigest: digest)
        let originalManifest = try FileTreeManifest.load(from: root.appendingPathComponent("source.json"), expectedDigest: record.sourceDigest)
        try verifyDestination(record, manifest: destinationManifest, paths: current)
        let source = try record.source(paths: current)
        var preserved: [URL] = []
        if preservingSource {
            if Self.exists(source) { preserved.append(source) }
            if let parent = try record.retirementParent(paths: current), Self.exists(parent) { preserved.append(parent) }
        } else {
            guard originalManifest.version >= 2, destinationManifest.version >= 2,
                  originalManifest.rootAttributes != nil, destinationManifest.rootAttributes != nil else {
                throw RuriError.message(Messages.CoreInstanceMover.cannotCleanOriginals)
            }
            if record.retirement == nil {
                guard record.sourceIdentity.matches(source) else { throw RuriError.message(Messages.CoreInstanceMover.originalIdentityChanged) }
                try originalManifest.requireMatch(in: source)
                // An interruption before saving this empty parent's identity can
                // leave only an empty folder; recovery creates another unique one.
                let token = UUID()
                let parent = try LauncherPaths.safePath("instances/.ruri-instance-move-source-\(record.id.uuidString)-\(token.uuidString)", within: record.sourceCollection?.url ?? current.root)
                guard mkdir(parent.path, S_IRWXU) == 0 else { throw RuriError.message(Messages.CoreInstanceMover.cleanupDirectoryFailed) }
                record.retirement = .init(token: token, identity: try .read(parent)); record.phase = .retiring
                try record.save(paths: current)
            }
            guard let parent = try record.retirementParent(paths: current), let retired = try record.retiredSource(paths: current),
                  record.retirement?.identity.matches(parent) == true || (record.phase == .deleting && !Self.exists(parent)) else { throw RuriError.message(Messages.CoreInstanceMover.retiredDirectoryIdentityChanged) }
            if record.phase != .deleting {
                progress(.init(phase: .retiring))
                if Self.exists(source) {
                    guard record.sourceIdentity.matches(source), !Self.exists(retired) else { throw RuriError.message(Messages.CoreInstanceMover.unexpectedOriginalFiles) }
                    try originalManifest.requireMatch(in: source)
                    guard rename(source.path, retired.path) == 0 else { throw RuriError.message(Messages.CoreInstanceMover.cleanupOriginalFilesFailed) }
                }
                guard record.sourceIdentity.matches(retired) else { throw RuriError.message(Messages.CoreInstanceMover.retiredLocationUnknown) }
                try originalManifest.requireMatch(in: retired)
                try verifyDestination(record, manifest: destinationManifest, paths: current)
                record.phase = .deleting; try record.save(paths: current)
            }
            progress(.init(phase: .deleting))
            // Only this phase allows missing original files after interrupted
            // removal; additions and byte changes still prevent further deletion.
            try verifyDestination(record, manifest: destinationManifest, paths: current)
            if Self.exists(retired) {
                guard record.sourceIdentity.matches(retired) else { throw RuriError.message(Messages.CoreInstanceMover.remainingDirectoryIdentityChanged) }
                try originalManifest.requireRemainingMatch(in: retired)
                try FileManager.default.removeItem(at: retired)
            }
            // rmdir never removes files a user may have added to the parent.
            if Self.exists(parent), rmdir(parent.path) != 0 { preserved.append(parent) }
            if Self.exists(source) { preserved.append(source) }
        }
        let workspace = try record.workspace(paths: current)
        if Self.exists(workspace) {
            if record.workspaceIdentity?.matches(workspace) == true {
                do { try FileManager.default.removeItem(at: workspace) } catch { preserved.append(workspace) }
            } else { preserved.append(workspace) }
        }
        let retiredRecord = try retireRecord(record, paths: current)
        if preserved.isEmpty {
            do { try FileManager.default.removeItem(at: retiredRecord) } catch { preserved.append(retiredRecord) }
        }
        return .init(state: state, preservedFiles: preserved, warning: preserved.isEmpty ? nil : Messages.CoreInstanceMover.originalOrWorkspaceFilesRetained.localized)
    }

    private func abandon(_ input: InstanceMoveJournal, paths: LauncherPaths) throws -> [URL] {
        var record = input
        try record.validateLocations(paths: paths)
        guard record.retirement == nil else { throw RuriError.message(Messages.CoreInstanceMover.cleanupSkippedFiles) }
        record.phase = .recovering; try record.save(paths: paths)
        let destination = try record.destination(paths: paths), workspace = try record.workspace(paths: paths)
        var preserved: [URL] = []
        if Self.exists(destination) {
            if (record.publishedIdentity ?? record.stagedIdentity)?.matches(destination) == true {
                guard record.workspaceIdentity?.matches(workspace) == true else { throw RuriError.message(Messages.CoreInstanceMover.workspaceIdentityChanged) }
                try RunDirectoryFileCopy.returnToWorkspace(destination, workspace: workspace)
            } else { preserved.append(destination) }
        }
        let retired = try retireRecord(record, paths: paths)
        preserved.append(Self.exists(workspace) ? workspace : retired)
        return preserved
    }
    private func retireRecord(_ record: InstanceMoveJournal, paths: LauncherPaths) throws -> URL {
        let target = try LauncherPaths.safePath("instance-move-recovery/\(record.original.id.uuidString)-\(record.id.uuidString)", within: paths.root)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunDirectoryFileCopy.moveWithoutReplacing(InstanceMoveJournal.root(paths: paths, instanceID: record.original.id), to: target)
        return target
    }
    private static func exists(_ url: URL) -> Bool { var info = stat(); return lstat(url.path, &info) == 0 || errno != ENOENT }
}
