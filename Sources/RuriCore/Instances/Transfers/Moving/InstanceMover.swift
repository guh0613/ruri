import Foundation
import Darwin

extension InstanceMover {
    public func move(_ preview: InstanceMovePreview, progress: @Sendable (InstanceMoveProgress) -> Void = { _ in }) async throws -> InstanceMoveResult {
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard state.instances.first(where: { $0.id == preview.source.id }) == preview.source else { throw RuriError.message("实例设置在预览后改变，请重新预览。") }
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
            guard mkdir(workspace.path, S_IRWXU) == 0 else { throw RuriError.message("无法创建移动工作区，已有文件未覆盖。") }
            record.workspaceIdentity = try .read(workspace); try record.save(paths: current); journal = record
            let location = record
            func checkLocations() throws {
                try location.validateLocations(paths: current)
                guard location.sourceIdentity.matches(preview.sourceDirectory), location.workspaceIdentity?.matches(workspace) == true else { throw RuriError.message("移动来源或工作区身份改变，文件已保留。") }
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
                guard let index = latest.instances.firstIndex(where: { $0.id == record.original.id }) else { throw RuriError.message("移动中的实例已被移除。") }
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
            catch { throw InstanceMoveFailure(message: "无法确认实例移动是否已经提交，请通过恢复入口检查。\(error.localizedDescription)", preservedFiles: [root], cancelled: Task.isCancelled) }
            if try journal.isCommitted(in: latest) {
                return .init(state: latest, preservedFiles: [root], warning: "实例已移动，原文件或工作记录还需检查。请恢复实例移动。\(reason)")
            }
            do {
                let preserved = try abandon(journal, paths: paths.configured(with: latest))
                throw InstanceMoveFailure(message: Task.isCancelled || error is CancellationError ? "移动已取消，原实例保留，工作副本已另存。" : "移动未完成，原实例保留。\(reason)", preservedFiles: preserved, cancelled: Task.isCancelled || error is CancellationError)
            } catch let failure as InstanceMoveFailure { throw failure }
            catch { throw InstanceMoveFailure(message: "移动未完成，原实例保留。请连接原磁盘并恢复移动。\(reason)\n\(error.localizedDescription)", preservedFiles: [root], cancelled: Task.isCancelled) }
        }
    }

    public func pending(instanceID: UUID) throws -> InstanceMoveRecovery? {
        guard InstanceMoveGuard.hasPending(paths: paths, instanceID: instanceID) else { return nil }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        let record = try InstanceMoveJournal.load(paths: current, instanceID: instanceID)
        return .init(id: record.id, instance: record.original, source: try record.source(paths: current),
                     destination: try record.destination(paths: current), workspace: try record.workspace(paths: current),
                     retiredSource: try record.retiredSource(paths: current), committed: try record.isCommitted(in: state))
    }

    public func recover(instanceID: UUID, transactionID: UUID, preservingSource: Bool = false, progress: @Sendable (InstanceMoveProgress) -> Void = { _ in }) throws -> InstanceMoveResult {
        let lease = try InstanceLocationLease.acquireForMoveRecovery(paths: paths, instanceID: instanceID)
        defer { withExtendedLifetime(lease) {} }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        let record = try InstanceMoveJournal.load(paths: current, instanceID: instanceID)
        guard record.id == transactionID else { throw RuriError.message("待恢复的移动已经改变，请刷新后重试。") }
        try record.validateLocations(paths: current)
        if try record.isCommitted(in: state) { return try finish(record, state: state, preservingSource: preservingSource, progress: progress) }
        return .init(state: state, preservedFiles: try abandon(record, paths: current), warning: "未完成的移动已恢复，原实例和工作副本保留。")
    }

    private func validateBinding(_ record: InstanceMoveJournal, in state: PersistentState) throws {
        guard state.instances.first(where: { $0.id == record.original.id }) == record.original else { throw RuriError.message("实例设置在预览后改变，请重新预览。") }
        try record.validateLocations(paths: paths.configured(with: state))
    }
    private func rebindModpack(_ root: URL, moved: GameInstance) throws {
        let file = root.appendingPathComponent("modpack-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var record = try ModpackRegistry.read(file, game: root.appendingPathComponent("minecraft"))
        record.settings.id = moved.id; record.settings.directoryID = moved.directoryID
        record.settings.runDirectory = moved.runDirectory; record.settings.customRunDirectory = moved.customRunDirectory
        record.settings.lastRunDirectoryChangeID = nil; record.settings.lastInstanceCopyID = nil; record.settings.lastInstanceMoveID = nil
        try JSONEncoder().encode(record).write(to: file, options: .atomic)
    }
    private func verifyDestination(_ record: InstanceMoveJournal, manifest: FileTreeManifest, paths: LauncherPaths) throws {
        let destination = try record.destination(paths: paths)
        guard (record.publishedIdentity ?? record.stagedIdentity)?.matches(destination) == true else { throw RuriError.message("移动目标的身份改变，原文件已保留。") }
        try manifest.requireMatch(in: destination)
    }

    private func finish(_ input: InstanceMoveJournal, state: PersistentState, preservingSource: Bool, progress: @Sendable (InstanceMoveProgress) -> Void) throws -> InstanceMoveResult {
        let current = paths.configured(with: state)
        var record = input
        try record.validateLocations(paths: current)
        guard try record.isCommitted(in: state), let digest = record.destinationDigest else { throw RuriError.message("移动尚未提交，不能清理原文件。") }
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
            if record.retirement == nil {
                guard record.sourceIdentity.matches(source) else { throw RuriError.message("原实例文件夹的身份改变，已保留，请检查后选择保留原文件完成移动。") }
                try originalManifest.requireMatch(in: source)
                // An interruption before saving this empty parent's identity can
                // leave only an empty folder; recovery creates another unique one.
                let token = UUID()
                let parent = try LauncherPaths.safePath("instances/.ruri-instance-move-source-\(record.id.uuidString)-\(token.uuidString)", within: record.sourceCollection?.url ?? current.root)
                guard mkdir(parent.path, S_IRWXU) == 0 else { throw RuriError.message("无法准备原文件清理目录。") }
                record.retirement = .init(token: token, identity: try .read(parent)); record.phase = .retiring
                try record.save(paths: current)
            }
            guard let parent = try record.retirementParent(paths: current), let retired = try record.retiredSource(paths: current),
                  record.retirement?.identity.matches(parent) == true || (record.phase == .deleting && !Self.exists(parent)) else { throw RuriError.message("原文件清理目录的身份改变，文件已保留。") }
            if record.phase != .deleting {
                progress(.init(phase: .retiring))
                if Self.exists(source) {
                    guard record.sourceIdentity.matches(source), !Self.exists(retired) else { throw RuriError.message("原位置出现其他文件，已保留，请检查后继续。") }
                    try originalManifest.requireMatch(in: source)
                    guard rename(source.path, retired.path) == 0 else { throw RuriError.message("无法整理原实例文件，移动记录已保留。") }
                }
                guard record.sourceIdentity.matches(retired) else { throw RuriError.message("无法确认原实例文件的退役位置。") }
                try originalManifest.requireMatch(in: retired)
                try verifyDestination(record, manifest: destinationManifest, paths: current)
                record.phase = .deleting; try record.save(paths: current)
            }
            progress(.init(phase: .deleting))
            // Only this phase allows missing original files after interrupted
            // removal; additions and byte changes still prevent further deletion.
            try verifyDestination(record, manifest: destinationManifest, paths: current)
            if Self.exists(retired) {
                guard record.sourceIdentity.matches(retired) else { throw RuriError.message("剩余原文件的目录身份改变，未继续清理。") }
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
        return .init(state: state, preservedFiles: preserved, warning: preserved.isEmpty ? nil : "实例已移动，部分原文件或工作文件保留，可在 Finder 中检查。")
    }

    private func abandon(_ input: InstanceMoveJournal, paths: LauncherPaths) throws -> [URL] {
        var record = input
        try record.validateLocations(paths: paths)
        guard record.retirement == nil else { throw RuriError.message("移动记录包含原文件清理信息，但找不到提交凭据，请先检查实例状态。") }
        record.phase = .recovering; try record.save(paths: paths)
        let destination = try record.destination(paths: paths), workspace = try record.workspace(paths: paths)
        var preserved: [URL] = []
        if Self.exists(destination) {
            if (record.publishedIdentity ?? record.stagedIdentity)?.matches(destination) == true {
                guard record.workspaceIdentity?.matches(workspace) == true else { throw RuriError.message("工作区身份改变，目标文件已原地保留。") }
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
