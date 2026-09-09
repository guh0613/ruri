import Foundation
import Darwin

public struct RunDirectoryCopyProgress: Sendable {
    public enum Phase: String, Sendable { case copying, publishing, committed }
    public let phase: Phase
    public let completed: Int
    public let total: Int
    public let bytesCopied: Int64
    public let totalBytes: Int64
    public var progress: InstallProgress {
        switch phase {
        case .copying: .init("正在复制游戏文件（\(ByteCountFormatter.string(fromByteCount: bytesCopied, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))）", completed: completed, total: total)
        case .publishing: .init("正在发布复制的文件", completed: completed, total: total)
        case .committed: .init("目录已更新，正在清理复制记录", completed: 1, total: 1)
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
    public var errorDescription: String? { message + (preservedCopy.map { "\n工作副本保留在：\($0.path)" } ?? "") }
}

extension GameRunDirectoryChange {
    public func copyToEmpty(_ preview: GameRunDirectoryChangePreview, progress: @Sendable (RunDirectoryCopyProgress) -> Void = { _ in }) async throws -> RunDirectoryCopyResult {
        guard preview.canCopyToTarget else { throw RuriError.message("目标已有文件或备份，不能以复制方式覆盖。请使用目标现有内容或选择空目录。") }
        let initial = try StateStore.load(paths)
        let current = paths.configured(with: initial)
        let instance = try find(preview.instanceID, in: initial)
        try validatePreviewBinding(preview, instance: instance, paths: current)
        let access = try await acquire(instance: instance, paths: current, target: preview.targetMode)
        defer { withExtendedLifetime(access) {} }
        try validateSnapshots(preview, access: access)
        // Upgrade before any copy can become pending, so old clients cannot
        // read a state that lacks knowledge of the new persistent reservation.
        try StateStore.update(paths) { state in try validatePreviewBinding(preview, instance: find(instance.id, in: state), paths: paths.configured(with: state)) }
        let root = try RunDirectoryCopyJournal.root(paths: current, instanceID: instance.id)
        let preparing = try LauncherPaths.safePath(".run-directory-change-\(UUID().uuidString)", within: current.instance(instance.id))
        var journal = RunDirectoryCopyJournal(id: UUID(), original: instance, target: preview.targetMode, createdAt: Date(), phase: .copying, items: [],
                                              emptyDirectories: preview.targetSnapshot.game.filter(\.directory).map { .init(area: .game, path: $0.path) } + preview.targetSnapshot.metadata.filter(\.directory).map { .init(area: .metadata, path: $0.path) })
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
            try RunDirectoryFileCopy.entries(preview.sourceSnapshot.game, to: root.appendingPathComponent("incoming/game"), validate: validateLocations, progress: copied)
            try RunDirectoryFileCopy.entries(preview.sourceSnapshot.metadata, to: root.appendingPathComponent("incoming/metadata"), validate: validateLocations, progress: copied)
            try Task.checkCancellation()
            try validateSnapshots(preview, access: access)
            for area in [RunDirectoryCopyJournal.Area.game, .metadata] {
                let incoming = root.appendingPathComponent("incoming/" + area.rawValue)
                for url in try FileManager.default.contentsOfDirectory(at: incoming, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    journal.items.append(.init(area: area, name: url.lastPathComponent, identity: try .read(url)))
                }
            }
            guard journal.items.count <= 4096 else { throw RuriError.message("游戏目录的顶层项目过多，无法记录安全的发布过程。") }
            journal.phase = .publishing; try journal.save(paths: current)
            progress(.init(phase: .publishing, completed: 0, total: journal.items.count, bytesCopied: bytes, totalBytes: preview.sourceBytes))
            for (index, item) in journal.items.enumerated() {
                try Task.checkCancellation()
                try validateLocations()
                let destination = try journal.destination(item, paths: access.targetPaths)
                try removeEmptyTree(destination)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try RunDirectoryFileCopy.moveWithoutReplacing(journal.incoming(item, paths: current), to: destination)
                guard item.identity.matches(destination) else { throw RuriError.message("复制项目在发布时跨越磁盘或身份改变，已保留工作区。") }
                progress(.init(phase: .publishing, completed: index + 1, total: journal.items.count, bytesCopied: bytes, totalBytes: preview.sourceBytes))
            }
            try Task.checkCancellation()
            committed = try StateStore.update(paths) { state in
                let instance = try find(preview.instanceID, in: state)
                try validatePreviewBinding(preview, instance: instance, paths: paths.configured(with: state))
                let index = state.instances.firstIndex(where: { $0.id == instance.id })!
                state.instances[index].runDirectory = preview.targetMode
                state.instances[index].lastRunDirectoryChangeID = journal.id
            }
            progress(.init(phase: .committed, completed: 1, total: 1, bytesCopied: bytes, totalBytes: preview.sourceBytes))
            journal.phase = .committed; try journal.save(paths: current)
            let remainder = try cleanup(journal, access: access)
            return .init(state: committed!, preservedCopy: remainder, warning: cleanupWarning(remainder))
        } catch {
            if !activated {
                try? FileManager.default.removeItem(at: preparing)
                throw RunDirectoryCopyFailure(message: "运行目录复制尚未开始：\(error.localizedDescription)", preservedCopy: nil, cancelled: Task.isCancelled)
            }
            if committed == nil {
                do {
                    let saved = try StateStore.load(paths)
                    if saved.instances.first(where: { $0.id == instance.id })?.lastRunDirectoryChangeID == journal.id { committed = saved }
                } catch {
                    throw RunDirectoryCopyFailure(message: "无法确认目录设置是否已提交，工作区和占用记录已保留。请在实例设置中恢复：\(error.localizedDescription)", preservedCopy: nil, cancelled: Task.isCancelled)
                }
            }
            if let committed {
                return .init(state: committed, preservedCopy: nil, warning: "目录已切换，复制记录尚未清理。请在实例设置中完成恢复清理：\(error.localizedDescription)")
            }
            let reason = Task.isCancelled || error is CancellationError ? "运行目录复制已取消，原目录和设置未改动。" : "运行目录复制未完成：\(error.localizedDescription)"
            do {
                let preserved = try abandon(journal, access: access)
                throw RunDirectoryCopyFailure(message: reason, preservedCopy: preserved, cancelled: Task.isCancelled || error is CancellationError)
            } catch let failure as RunDirectoryCopyFailure { throw failure }
            catch { throw RunDirectoryCopyFailure(message: reason + "\n自动恢复尚未完成，请在实例设置中恢复复制。\(error.localizedDescription)", preservedCopy: nil, cancelled: Task.isCancelled) }
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
        var targetInstance = journal.original; targetInstance.runDirectory = journal.target
        return .init(owner: journal.owner, source: source.game(instance.id), target: current.including(targetInstance).game(instance.id), createdAt: journal.createdAt,
                     committed: instance.lastRunDirectoryChangeID == journal.id, workspace: try RunDirectoryCopyJournal.root(paths: current, instanceID: instance.id))
    }
    /// Recovery preserves an uncommitted working copy; a committed copy only
    /// needs cleanup. It never invents a successful commit or deletes originals.
    public func recoverCopy(instanceID: UUID, transactionID: UUID) throws -> RunDirectoryCopyResult {
        let state = try StateStore.load(paths)
        let current = paths.configured(with: state)
        let journal = try RunDirectoryCopyJournal.load(paths: current, instanceID: instanceID)
        guard journal.id == transactionID else { throw RuriError.message("待恢复的复制记录已经变化，请刷新后重试。") }
        let instance = try find(instanceID, in: state)
        try validateJournalBinding(journal, current: instance)
        let originalPaths = current.including(journal.original)
        let access = try RunDirectoryChangeAccess(instance: journal.original, paths: originalPaths, target: journal.target, directoryChangeID: journal.id)
        defer { withExtendedLifetime(access) {} }
        try access.lockFiles()
        let latest = try RunDirectoryCopyJournal.load(paths: current, instanceID: instanceID)
        guard latest.id == journal.id else { throw RuriError.message("复制记录已经变化。") }
        let freshState = try StateStore.load(paths), fresh = try find(instanceID, in: freshState)
        try validateJournalBinding(latest, current: fresh)
        if fresh.lastRunDirectoryChangeID == journal.id {
            let remainder = try cleanup(latest, access: access)
            return .init(state: freshState, preservedCopy: remainder, warning: cleanupWarning(remainder))
        }
        let copy = try abandon(latest, access: access)
        return .init(state: freshState, preservedCopy: copy, warning: nil)
    }
    private func validateJournalBinding(_ journal: RunDirectoryCopyJournal, current: GameInstance) throws {
        guard current.directoryID == journal.original.directoryID,
              current.gameVersion == journal.original.gameVersion, current.loader == journal.original.loader, current.loaderVersion == journal.original.loaderVersion,
              current.lastRunDirectoryChangeID == journal.id || current.runDirectory == journal.original.runDirectory else {
            throw RuriError.message("实例设置在复制中断后改变，工作区已保留，请先核对原实例。")
        }
    }
    private func removeEmptyTree(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let entries = try FileTree.entries(in: url)
        guard entries.allSatisfy(\.directory) else { throw RuriError.message("目标目录在发布前出现新文件，未覆盖这些内容。") }
        for entry in entries.sorted(by: { $0.path.count > $1.path.count }) {
            guard rmdir(entry.url.path) == 0 else { throw RuriError.message("目标空目录发生变化，未删除新增文件。") }
        }
        guard rmdir(url.path) == 0 else { throw RuriError.message("目标目录并非空目录，未替换。") }
    }
    private func cleanupWarning(_ remainder: URL?) -> String? {
        remainder == nil ? nil : "目录已切换，占用记录已清除。部分临时文件未能删除，可在 Finder 中查看保留的工作区。"
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
            try FileManager.default.removeItem(at: retired)
            _ = rmdir(retired.deletingLastPathComponent().path)
            return nil
        } catch { return retired }
    }
    private func abandon(_ input: RunDirectoryCopyJournal, access: RunDirectoryChangeAccess) throws -> URL {
        try access.sourcePaths.validateInstanceLocation(input.original.id)
        try access.targetPaths.validateInstanceLocation(input.original.id)
        var journal = input; journal.phase = .rollingBack; try journal.save(paths: access.sourcePaths)
        for item in journal.items.reversed() {
            let destination = try journal.destination(item, paths: access.targetPaths)
            // A foreign replacement remains untouched. Our directory inode can
            // contain later user edits; moving it back preserves those as well.
            guard item.identity.matches(destination) else { continue }
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
        return recovery
    }
}
