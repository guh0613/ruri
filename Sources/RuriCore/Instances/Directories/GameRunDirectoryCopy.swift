import RuriLocalization
import Foundation
import Darwin

public struct RunDirectoryCopyProgress: Sendable {
    public enum Phase: String, Sendable { case verifying, copying, publishing, committed }
    public let phase: Phase
    public let completed: Int
    public let total: Int
    public let bytesCopied: Int64
    public let totalBytes: Int64
    public var progress: InstallProgress {
        switch phase {
        case .verifying: .init(Messages.CoreGameRunDirectoryCopy.validatingFileContents, completed: completed, total: total)
        case .copying: .init(Messages.CoreGameRunDirectoryCopy.copyingGameFiles(String(describing: LocalizedFormat.bytes(bytesCopied)), String(describing: LocalizedFormat.bytes(totalBytes))), completed: completed, total: total)
        case .publishing: .init(Messages.CoreGameRunDirectoryCopy.writingDestination(String(describing: LocalizedFormat.bytes(bytesCopied)), String(describing: LocalizedFormat.bytes(totalBytes))), completed: totalBytes > 0 ? Int(bytesCopied) : completed, total: totalBytes > 0 ? Int(totalBytes) : total)
        case .committed: .init(Messages.CoreGameRunDirectoryCopy.cleaningCopyRecord, completed: 1, total: 1)
        }
    }
}
public struct RunDirectoryCopyRecovery: Sendable {
    public let owner: RunDirectoryCopyOwner
    public let source: URL
    public let target: URL
    public let createdAt: Date
    public let committed: Bool
    public let workspace: URL
}
public struct RunDirectoryCopyResult: Sendable {
    public let state: PersistentState
    public let preservedCopy: URL?
    public let warning: String?
}
public struct RunDirectoryCopyFailure: LocalizedError, Sendable {
    public let message: String
    public let preservedCopy: URL?
    public let cancelled: Bool
    public var errorDescription: String? { message + (preservedCopy.map { Messages.CoreGameRunDirectoryCopy.workCopyRetained($0.path).localized } ?? "") }
}

extension GameRunDirectoryChange {
    public func copyToEmpty(_ preview: GameRunDirectoryChangePreview, progress: @Sendable (RunDirectoryCopyProgress) -> Void = { _ in }) async throws -> RunDirectoryCopyResult {
        if let issue = preview.copyIssue { throw RuriError.message(issue) }
        guard preview.canCopyToTarget else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.destinationConflict) }
        let initial = try StateStore.load(paths)
        let current = paths.configured(with: initial)
        let instance = try find(preview.instanceID, in: initial)
        try validatePreviewBinding(preview, instance: instance, paths: current)
        let access = try await acquire(instance: instance, paths: current, target: preview.targetMode, customDirectory: preview.targetCustomDirectory)
        defer { withExtendedLifetime(access) {} }
        try validateSnapshots(preview, access: access)
        // Upgrade before any copy can become pending, so old clients cannot
        // read a state that lacks knowledge of the new persistent reservation.
        try StateStore.update(paths) { state in try validatePreviewBinding(preview, instance: find(instance.id, in: state), paths: paths.configured(with: state)) }
        let root = try RunDirectoryCopyJournal.root(paths: current, instanceID: instance.id)
        let preparing = try LauncherPaths.safePath(".run-directory-change-\(UUID().uuidString)", within: current.instance(instance.id))
        var journal = RunDirectoryCopyJournal(id: UUID(), original: instance, target: preview.targetMode, createdAt: Date(), phase: .copying, items: [],
                                              emptyDirectories: preview.targetSnapshot.game.filter(\.directory).map { .init(area: .game, path: $0.path) } + preview.targetSnapshot.metadata.filter(\.directory).map { .init(area: .metadata, path: $0.path) })
        journal.targetCustomDirectory = preview.targetCustomDirectory
        journal.stagingOnTarget = preview.targetMode == .custom
        let workspace = try journal.workspace(paths: current)
        var committed: PersistentState?
        var activated = false
        do {
            // Publish the work directory only after its first journal is complete.
            // A process dying earlier leaves no pending operation or copied files.
            try FileManager.default.createDirectory(at: preparing, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try journal.save(paths: current, at: preparing)
            try RunDirectoryFileCopy.moveWithoutReplacing(preparing, to: root); activated = true
            try RunDirectoryCopyGuard.mark(journal, paths: access.targetPaths)
            var bytes: Int64 = 0, completed = 0
            var lastProgress = Date.distantPast
            func copied(_ amount: Int64, _ fileCompleted: Bool) {
                bytes += amount; if fileCompleted { completed += 1 }
                if completed == preview.sourceFileCount || Date().timeIntervalSince(lastProgress) >= 0.1 {
                    lastProgress = Date(); progress(.init(phase: .copying, completed: completed, total: preview.sourceFileCount, bytesCopied: bytes, totalBytes: preview.sourceBytes))
                }
            }
            progress(.init(phase: .copying, completed: 0, total: preview.sourceFileCount, bytesCopied: 0, totalBytes: preview.sourceBytes))
            func validateLocations() throws { try access.sourcePaths.validateInstanceLocation(instance.id); try access.targetPaths.validateInstanceLocation(instance.id) }
            try RunDirectoryFileCopy.entries(preview.sourceSnapshot.game, to: workspace.appendingPathComponent("incoming/game"), validate: validateLocations, progress: copied)
            try RunDirectoryFileCopy.entries(preview.sourceSnapshot.metadata, to: workspace.appendingPathComponent("incoming/metadata"), validate: validateLocations, progress: copied)
            try Task.checkCancellation()
            try validateSnapshots(preview, access: access)
            for area in [RunDirectoryCopyJournal.Area.game, .metadata] {
                let incoming = workspace.appendingPathComponent("incoming/" + area.rawValue)
                for url in try FileManager.default.contentsOfDirectory(at: incoming, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    journal.items.append(.init(area: area, name: url.lastPathComponent, identity: try .read(url)))
                }
            }
            guard journal.items.count <= 4096 else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.tooManyTopLevelItems) }
            journal.phase = .publishing; try journal.save(paths: current)
            var sizes: [String: Int64] = [:]
            for (area, entries) in [(RunDirectoryCopyJournal.Area.game, preview.sourceSnapshot.game), (.metadata, preview.sourceSnapshot.metadata)] {
                for entry in entries where !entry.directory {
                    sizes[area.rawValue + "/" + String(entry.path.split(separator: "/")[0]), default: 0] += entry.size
                }
            }
            var publishedBytes: Int64 = 0
            progress(.init(phase: .publishing, completed: 0, total: journal.items.count, bytesCopied: 0, totalBytes: preview.sourceBytes))
            for (index, item) in journal.items.enumerated() {
                try Task.checkCancellation()
                try validateLocations()
                let destination = try journal.destination(item, paths: access.targetPaths)
                try removeEmptyTree(destination)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let completedBytes = publishedBytes
                try RunDirectoryFileCopy.publish(journal.incoming(item, paths: current), to: destination, directory: item.identity.directory) { identity in
                    journal.items[index].publishedIdentity = identity; try journal.save(paths: current)
                } validate: { try validateLocations() } progress: { amount in
                    publishedBytes += amount
                    progress(.init(phase: .publishing, completed: index, total: journal.items.count, bytesCopied: publishedBytes, totalBytes: preview.sourceBytes))
                }
                guard (journal.items[index].publishedIdentity ?? item.identity).matches(destination) else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.publishedItemChanged) }
                publishedBytes = completedBytes + (sizes[item.area.rawValue + "/" + item.name] ?? 0)
                progress(.init(phase: .publishing, completed: index + 1, total: journal.items.count, bytesCopied: publishedBytes, totalBytes: preview.sourceBytes))
            }
            try Task.checkCancellation()
            committed = try StateStore.update(paths) { state in
                let instance = try find(preview.instanceID, in: state)
                try validatePreviewBinding(preview, instance: instance, paths: paths.configured(with: state))
                let index = state.instances.firstIndex(where: { $0.id == instance.id })!
                state.instances[index].runDirectory = preview.targetMode
                if preview.targetMode == .custom { state.instances[index].customRunDirectory = preview.targetCustomDirectory }
                state.instances[index].lastRunDirectoryChangeID = journal.id
            }
            progress(.init(phase: .committed, completed: 1, total: 1, bytesCopied: bytes, totalBytes: preview.sourceBytes))
            journal.phase = .committed; try journal.save(paths: current)
            let remainder = try cleanup(journal, access: access)
            return .init(state: committed!, preservedCopy: remainder, warning: cleanupWarning(remainder))
        } catch {
            if !activated {
                try? FileManager.default.removeItem(at: preparing)
                throw RunDirectoryCopyFailure(message: Messages.CoreGameRunDirectoryCopy.copyNotStarted(error.localizedDescription).localized, preservedCopy: nil, cancelled: Task.isCancelled)
            }
            if committed == nil {
                do {
                    let saved = try StateStore.load(paths)
                    if saved.instances.first(where: { $0.id == instance.id })?.lastRunDirectoryChangeID == journal.id { committed = saved }
                } catch {
                    throw RunDirectoryCopyFailure(message: Messages.CoreGameRunDirectoryCopy.directorySettingsUnconfirmed(error.localizedDescription).localized, preservedCopy: nil, cancelled: Task.isCancelled)
                }
            }
            if let committed {
                return .init(state: committed, preservedCopy: nil, warning: Messages.CoreGameRunDirectoryCopy.directorySwitchedCleanupPending(error.localizedDescription).localized)
            }
            let reason = Task.isCancelled || error is CancellationError ? Messages.CoreGameRunDirectoryCopy.copyCancelled.localized : Messages.CoreGameRunDirectoryCopy.copyIncomplete(error.localizedDescription).localized
            do {
                let preserved = try abandon(journal, access: access)
                throw RunDirectoryCopyFailure(message: reason + (preserved.warning.map { "\n" + $0 } ?? ""), preservedCopy: preserved.workspace, cancelled: Task.isCancelled || error is CancellationError)
            } catch let failure as RunDirectoryCopyFailure { throw failure }
            catch { throw RunDirectoryCopyFailure(message: Messages.CoreGameRunDirectoryCopy.recoveryFailure(reason, error.localizedDescription).localized, preservedCopy: nil, cancelled: Task.isCancelled) }
        }
    }

    public func pendingCopy(instanceID: UUID) throws -> RunDirectoryCopyRecovery? {
        let state = try StateStore.load(paths)
        let current = paths.configured(with: state)
        guard let owner = try RunDirectoryCopyGuard.owner(paths: current, instanceID: instanceID) else { return nil }
        let journal = try RunDirectoryCopyJournal.load(paths: current, instanceID: owner.instanceID)
        let instance = try find(owner.instanceID, in: state)
        try validateJournalBinding(journal, current: instance)
        let source = current.including(journal.original)
        let workspace = try journal.workspace(paths: current)
        return .init(owner: journal.owner, source: source.game(instance.id), target: journal.targetPaths(current).game(instance.id), createdAt: journal.createdAt,
                     committed: instance.lastRunDirectoryChangeID == journal.id,
                     workspace: FileManager.default.fileExists(atPath: workspace.path) ? workspace : try RunDirectoryCopyJournal.root(paths: current, instanceID: instance.id))
    }
    /// Recovery preserves an uncommitted working copy; a committed copy only
    /// needs cleanup. It never invents a successful commit or deletes originals.
    public func recoverCopy(instanceID: UUID, transactionID: UUID) throws -> RunDirectoryCopyResult {
        let state = try StateStore.load(paths)
        let current = paths.configured(with: state)
        let journal = try RunDirectoryCopyJournal.load(paths: current, instanceID: instanceID)
        guard journal.id == transactionID else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.copyJournalChanged) }
        let instance = try find(instanceID, in: state)
        try validateJournalBinding(journal, current: instance)
        let originalPaths = current.including(journal.original)
        let access = try RunDirectoryChangeAccess(instance: journal.original, paths: originalPaths, target: journal.target, customDirectory: journal.targetCustomDirectory, directoryChangeID: journal.id)
        defer { withExtendedLifetime(access) {} }
        try access.lockFiles()
        let latest = try RunDirectoryCopyJournal.load(paths: current, instanceID: instanceID)
        guard latest.id == journal.id else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.copyRecordChanged) }
        let freshState = try StateStore.load(paths), fresh = try find(instanceID, in: freshState)
        try validateJournalBinding(latest, current: fresh)
        if fresh.lastRunDirectoryChangeID == journal.id {
            let remainder = try cleanup(latest, access: access)
            return .init(state: freshState, preservedCopy: remainder, warning: cleanupWarning(remainder))
        }
        let copy = try abandon(latest, access: access)
        return .init(state: freshState, preservedCopy: copy.workspace, warning: copy.warning)
    }
    private func validateJournalBinding(_ journal: RunDirectoryCopyJournal, current: GameInstance) throws {
        guard current.directoryID == journal.original.directoryID,
              current.repositoryVersionID == journal.original.repositoryVersionID,
              current.gameVersion == journal.original.gameVersion, current.loader == journal.original.loader, current.loaderVersion == journal.original.loaderVersion,
              current.lastRunDirectoryChangeID == journal.id || current.runDirectory == journal.original.runDirectory else {
            throw RuriError.message(Messages.CoreGameRunDirectoryCopy.instanceSettingsChangedDuringCopy)
        }
        if current.lastRunDirectoryChangeID != journal.id, journal.original.runDirectory == .custom {
            guard let expected = journal.original.customRunDirectory, current.customRunDirectory?.isSameLocation(as: expected) == true else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.sourceDirectoryChangedDuringCopy) }
        }
    }
    private func removeEmptyTree(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let entries = try FileTree.entries(in: url)
        guard entries.allSatisfy(\.directory) else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.newDestinationFiles) }
        for entry in entries.sorted(by: { $0.path.count > $1.path.count }) {
            guard rmdir(entry.url.path) == 0 else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.newFilesInEmptyDestination) }
        }
        guard rmdir(url.path) == 0 else { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.destinationNotEmpty) }
    }
    private func cleanupWarning(_ remainder: URL?) -> String? {
        remainder == nil ? nil : Messages.CoreGameRunDirectoryCopy.temporaryFilesCleanupWarning.localized
    }
    private func cleanup(_ journal: RunDirectoryCopyJournal, access: RunDirectoryChangeAccess) throws -> URL? {
        try access.sourcePaths.validateInstanceLocation(journal.original.id)
        try access.targetPaths.validateInstanceLocation(journal.original.id)
        let retired = try LauncherPaths.safePath("directory-change-recovery/\(journal.id.uuidString)-completed-\(UUID().uuidString)", within: access.sourcePaths.instance(journal.original.id))
        try FileManager.default.createDirectory(at: retired.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunDirectoryCopyGuard.clear(journal, paths: access.targetPaths)
        // Retire atomically before recursive cleanup. A process dying while
        // deleting temporary files must not leave an unreadable pending journal.
        try RunDirectoryFileCopy.moveWithoutReplacing(RunDirectoryCopyJournal.root(paths: access.sourcePaths, instanceID: journal.original.id), to: retired)
        do {
            if journal.stagingOnTarget == true {
                let workspace = try journal.workspace(paths: access.sourcePaths)
                if FileManager.default.fileExists(atPath: workspace.path) {
                    do { try FileManager.default.removeItem(at: workspace); _ = rmdir(workspace.deletingLastPathComponent().path) }
                    catch { return workspace }
                }
            }
            try FileManager.default.removeItem(at: retired)
            _ = rmdir(retired.deletingLastPathComponent().path)
            return nil
        } catch { return retired }
    }
    private func abandon(_ input: RunDirectoryCopyJournal, access: RunDirectoryChangeAccess) throws -> (workspace: URL, warning: String?) {
        try access.sourcePaths.validateInstanceLocation(input.original.id)
        try access.targetPaths.validateInstanceLocation(input.original.id)
        var journal = input; journal.phase = .rollingBack; try journal.save(paths: access.sourcePaths)
        var retained: [String] = []
        for item in journal.items.reversed() {
            let destination = try journal.destination(item, paths: access.targetPaths)
            // A foreign replacement remains untouched. Our directory inode can
            // contain later user edits; moving it back preserves those as well.
            guard (item.publishedIdentity ?? item.identity).matches(destination) else {
                var info = stat()
                if lstat(destination.path, &info) == 0 { retained.append(item.name) }
                else if errno != ENOENT { throw RuriError.message(Messages.CoreGameRunDirectoryCopy.destinationInspectionFailed(item.name)) }
                continue
            }
            if item.publishedIdentity != nil {
                // The complete staging copy still exists. Preserve the partial
                // publication separately, including any subsequent user edits.
                try RunDirectoryFileCopy.returnToWorkspace(destination, workspace: journal.workspace(paths: access.sourcePaths))
                continue
            }
            let incoming = try journal.incoming(item, paths: access.sourcePaths)
            try FileManager.default.createDirectory(at: incoming.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RunDirectoryFileCopy.moveWithoutReplacing(destination, to: incoming)
        }
        for directory in journal.emptyDirectories.sorted(by: { $0.path.count < $1.path.count }) {
            let root = directory.area == .game ? access.targetPaths.game(journal.original.id) : access.targetPaths.gameDataState(journal.original.id)
            let url = try LauncherPaths.safePath(directory.path, within: root)
            if !FileManager.default.fileExists(atPath: url.path) { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        }
        let recovery = try LauncherPaths.safePath("directory-change-recovery/\(journal.id.uuidString)-\(UUID().uuidString)", within: access.sourcePaths.instance(journal.original.id))
        try FileManager.default.createDirectory(at: recovery.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunDirectoryCopyGuard.clear(journal, paths: access.targetPaths)
        try RunDirectoryFileCopy.moveWithoutReplacing(RunDirectoryCopyJournal.root(paths: access.sourcePaths, instanceID: journal.original.id), to: recovery)
        let warning = retained.isEmpty ? nil : Messages.CoreGameRunDirectoryCopy.changedFileIdentitiesRetained(Int64(retained.count), String(describing: retained.prefix(5).joined(separator: "、"))).localized
        if journal.stagingOnTarget == true {
            let workspace = try journal.workspace(paths: access.sourcePaths)
            if FileManager.default.fileExists(atPath: workspace.path) { return (workspace, warning) }
        }
        return (recovery, warning)
    }
}
