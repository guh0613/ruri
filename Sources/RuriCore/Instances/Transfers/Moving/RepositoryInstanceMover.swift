import Foundation
import Darwin

extension InstanceMover {
    func moveRepository(_ preview: InstanceMovePreview, progress: @Sendable (InstanceMoveProgress) -> Void) async throws -> InstanceMoveResult {
        guard let snapshot = preview.repository else { throw RuriError.message("移动预览缺少安装文件。") }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard state.instances.first(where: { $0.id == preview.source.id }) == preview.source else { throw RuriError.message("实例设置在预览后改变，请重新预览。") }
        let access = try await InstanceMoveAccess.acquire(instance: preview.source, paths: current)
        defer { withExtendedLifetime(access) {} }
        try requireIndependentVersion(preview.source, paths: current)
        progress(.init(phase: .verifying))
        try requireRepositoryUnchanged(preview, paths: current)
        let root = try InstanceMoveJournal.root(paths: paths, instanceID: preview.source.id)
        let preparing = root.deletingLastPathComponent().appendingPathComponent(".preparing-" + preview.id.uuidString)
        try FileManager.default.createDirectory(at: preparing, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: preparing) }
        var sources: [RepositoryMoveJournal.FileSet] = [.init(part: .metadata, identity: preview.sourceIdentity,
            digest: try preview.snapshot.original.save(to: preparing.appendingPathComponent("source-metadata.json")))]
        if let version = snapshot.sourceVersion, let identity = snapshot.sourceVersionIdentity {
            sources.append(.init(part: .version, identity: identity, digest: try version.save(to: preparing.appendingPathComponent("source-version.json"))))
        }
        var record = RepositoryMoveJournal(id: preview.id, original: preview.source, moved: preview.moved,
                                           sourceCollection: preview.sourceCollection, targetCollection: preview.targetCollection, sources: sources)
        try record.validateLocations(paths: current)
        for part in destinationParts(record) { try Self.requireAbsent(record.destination(part, paths: current)) }
        try StateStore.update(paths) { latest in
            guard latest.instances.first(where: { $0.id == preview.source.id }) == preview.source else { throw RuriError.message("实例设置已改变，请重新预览。") }
        }
        try record.save(paths: current, at: preparing)
        try RunDirectoryFileCopy.moveWithoutReplacing(preparing, to: root)
        do {
            let workspace = try record.workspace(paths: current)
            try FileManager.default.createDirectory(at: workspace.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard mkdir(workspace.path, S_IRWXU) == 0 else { throw RuriError.message("移动工作区已存在，未覆盖已有文件。") }
            record.workspaceIdentity = try .read(workspace); try record.save(paths: current)
            try record.reserveVersions()
            let location = record
            @Sendable func validate() throws {
                try location.validateLocations(paths: current)
                guard location.workspaceIdentity?.matches(workspace) == true else { throw RuriError.message("移动工作区身份改变。") }
            }
            var copied: Int64 = 0, lastUpdate = Date.distantPast
            progress(.init(phase: .copying, totalBytes: preview.bytes))
            try RunDirectoryFileCopy.entries(preview.snapshot.entries, to: workspace, validate: validate) { amount, _ in
                copied += amount
                if Date().timeIntervalSince(lastUpdate) >= 0.1 {
                    lastUpdate = Date(); progress(.init(phase: .copying, bytesCopied: copied, totalBytes: preview.bytes))
                }
            }
            for part in destinationParts(record) { try FileManager.default.createDirectory(at: record.incoming(part, paths: current), withIntermediateDirectories: true) }
            try preview.snapshot.destination.requireMatch(in: workspace, excluding: ["reservation.json"])
            let metadata = try record.incoming(.metadata, paths: current)
            let resourceRoot = record.moved.repositoryVersionID == nil ? metadata.appendingPathComponent("installation") : record.targetCollection!.url
            let name = record.moved.repositoryVersionID ?? "game"
            let version = record.moved.repositoryVersionID == nil ? resourceRoot.appendingPathComponent("versions/" + name) : try record.incoming(.version, paths: current)
            try await snapshot.installation.write(resourceRoot: resourceRoot, clientFile: version.appendingPathComponent(name + ".jar"),
                manifestFile: record.moved.repositoryVersionID == nil ? metadata.appendingPathComponent("version.json") : version.appendingPathComponent(name + ".json"),
                metadata: metadata, validate: validate) { value in
                    progress(.init(phase: .copying, bytesCopied: min(preview.bytes, Int64(value.fraction * Double(snapshot.installation.bytes)) + preview.snapshot.destination.entries.reduce(Int64(0)) { $0 + $1.size }), totalBytes: preview.bytes))
                }
            try rebindRepositoryMovePack(metadata, moved: record.moved, game: record.moved.runDirectory == .custom ? current.game(record.original.id) : record.moved.repositoryVersionID == nil ? metadata.appendingPathComponent("minecraft") : version)
            try requireRepositoryUnchanged(preview, paths: current)
            for part in destinationParts(record) {
                let incoming = try record.incoming(part, paths: current)
                let digest = try FileTreeManifest.capture(in: incoming).save(to: root.appendingPathComponent("target-" + part.rawValue + ".json"))
                record.publications.append(.init(part: part, staged: try .read(incoming), digest: digest))
            }
            if record.moved.repositoryVersionID != nil {
                record.resources = snapshot.installation.resources.map { .init(path: $0.path, sha1: $0.sha1, size: $0.size) }
                record.resources += snapshot.installation.generatedResources.map { .init(path: $0.key, sha1: MinecraftInstallationCopy.sha1($0.value), size: Int64($0.value.count)) }
            }
            record.phase = .publishing; try record.save(paths: current)
            progress(.init(phase: .publishing, totalBytes: preview.bytes))
            for index in record.publications.indices {
                let part = record.publications[index].part
                let destination = try record.destination(part, paths: current)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try RunDirectoryFileCopy.publish(record.incoming(part, paths: current), to: destination, directory: true, ignoringTransientFiles: false,
                    created: { record.publications[index].published = $0; try record.save(paths: current) }, validate: validate, progress: { _ in })
            }
            try Task.checkCancellation()
            try requireRepositoryUnchanged(preview, paths: current)
            try verifyRepositoryDestination(record, paths: current)
            try access.lease.clearFinishedReservation(paths: current, instanceID: preview.source.id)
            let saved = try StateStore.update(paths) { latest in
                guard let index = latest.instances.firstIndex(where: { $0.id == preview.source.id }), latest.instances[index] == preview.source else { throw RuriError.message("实例设置在移动期间改变。") }
                try record.validateLocations(paths: current)
                latest.instances[index] = record.moved; latest.selectedDirectoryID = record.moved.directoryID; latest.selectedInstanceID = record.moved.id
            }
            progress(.init(phase: .committed))
            record.phase = .committed; try record.save(paths: current)
            return try finishRepository(record, state: saved, preservingSource: false, progress: progress)
        } catch {
            let saved = try StateStore.load(paths)
            if try record.isCommitted(saved) { return .init(state: saved, preservedFiles: [root], warning: "实例已移动，原文件与工作记录尚需处理，请恢复实例移动。\(error.localizedDescription)") }
            let reason = error.localizedDescription
            do {
                let kept = try abandonRepository(record, paths: current)
                throw InstanceMoveFailure(message: Task.isCancelled || error is CancellationError ? "移动已取消，原实例保留，工作副本已另存。" : "移动未完成，原实例保留。\(reason)", preservedFiles: kept, cancelled: Task.isCancelled || error is CancellationError)
            } catch let failure as InstanceMoveFailure { throw failure }
            catch { throw InstanceMoveFailure(message: "移动需要恢复，原实例保留。\(reason)\n\(error.localizedDescription)", preservedFiles: [root], cancelled: Task.isCancelled) }
        }
    }

    func repositoryPending(_ instanceID: UUID, state: PersistentState) throws -> InstanceMoveRecovery {
        let record = try RepositoryMoveJournal.load(paths: paths, instanceID: instanceID)
        return .init(id: record.id, instance: record.original,
                     source: try record.source(record.original.repositoryVersionID == nil ? .metadata : .version, paths: paths),
                     destination: try record.destination(record.moved.repositoryVersionID == nil ? .metadata : .version, paths: paths),
                     workspace: try record.workspace(paths: paths), retiredSource: record.retirementIdentity == nil ? nil : try record.retirement(paths: paths), committed: try record.isCommitted(state))
    }
    func recoverRepository(_ instanceID: UUID, transactionID: UUID, state: PersistentState, preservingSource: Bool, progress: @Sendable (InstanceMoveProgress) -> Void) throws -> InstanceMoveResult {
        let record = try RepositoryMoveJournal.load(paths: paths, instanceID: instanceID)
        guard record.id == transactionID else { throw RuriError.message("待恢复的移动已经改变。") }
        try record.validateLocations(paths: paths)
        if try record.isCommitted(state) { return try finishRepository(record, state: state, preservingSource: preservingSource, progress: progress) }
        return .init(state: state, preservedFiles: try abandonRepository(record, paths: paths), warning: "未完成的移动已恢复，原实例及工作副本保留。")
    }
    private func destinationParts(_ record: RepositoryMoveJournal) -> [RepositoryMoveJournal.Part] { record.moved.repositoryVersionID == nil ? [.metadata] : [.metadata, .version] }
    private func rebindRepositoryMovePack(_ metadata: URL, moved: GameInstance, game: URL) throws {
        let file = metadata.appendingPathComponent("modpack-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var pack = try ModpackRegistry.read(file, game: game)
        pack.settings.directoryID = moved.directoryID; pack.settings.repositoryVersionID = moved.repositoryVersionID
        pack.settings.importedInstallation = moved.importedInstallation; pack.settings.runDirectory = moved.runDirectory; pack.settings.customRunDirectory = moved.customRunDirectory
        try FileExtendedAttributes.rewrite(JSONEncoder().encode(pack), at: file)
    }
    private func verifyRepositoryDestination(_ record: RepositoryMoveJournal, paths: LauncherPaths, contents: Bool = true) throws {
        guard record.publications.map(\.part) == destinationParts(record) else { throw RuriError.message("移动目标尚未完整发布。") }
        let root = try InstanceMoveJournal.root(paths: paths, instanceID: record.original.id)
        for publication in record.publications {
            let target = try record.destination(publication.part, paths: paths)
            guard (publication.published ?? publication.staged).matches(target) else { throw RuriError.message("移动目标的身份改变，原文件已保留。") }
            if contents { try FileTreeManifest.load(from: root.appendingPathComponent("target-" + publication.part.rawValue + ".json"), expectedDigest: publication.digest).requireMatch(in: target) }
        }
        if contents, let directory = record.targetCollection, record.moved.repositoryVersionID != nil {
            for resource in record.resources { try MinecraftInstallationFiles.requireResource(LauncherPaths.safePath(resource.path, within: directory.url), sha1: resource.sha1, size: resource.size) }
        }
    }
    private func finishRepository(_ input: RepositoryMoveJournal, state: PersistentState, preservingSource: Bool, progress: @Sendable (InstanceMoveProgress) -> Void) throws -> InstanceMoveResult {
        var record = input
        try record.validateLocations(paths: paths)
        guard try record.isCommitted(state) else { throw RuriError.message("移动尚未提交，不能清理原文件。") }
        progress(.init(phase: .verifying))
        try verifyRepositoryDestination(record, paths: paths, contents: !preservingSource)
        let root = try InstanceMoveJournal.root(paths: paths, instanceID: record.original.id), retired = try record.retirement(paths: paths)
        var kept: [URL] = []
        if preservingSource {
            kept += try record.sources.map { try record.source($0.part, paths: paths) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            if FileManager.default.fileExists(atPath: retired.path) { kept.append(retired) }
        } else {
            let current = paths.configured(with: state).including(record.original)
            if record.phase != .deleting { try requireIndependentVersion(record.original, paths: current) }
            if record.retirementIdentity == nil {
                for source in record.sources {
                    let location = try record.source(source.part, paths: paths)
                    guard source.identity.matches(location) else { throw RuriError.message("原文件夹身份改变，请检查或选择保留原文件完成移动。") }
                    try FileTreeManifest.load(from: root.appendingPathComponent("source-" + source.part.rawValue + ".json"), expectedDigest: source.digest).requireMatch(in: location)
                }
                try FileManager.default.createDirectory(at: retired.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard mkdir(retired.path, S_IRWXU) == 0 else { throw RuriError.message("无法创建原文件清理目录。") }
                record.retirementIdentity = try .read(retired); record.phase = .retiring; try record.save(paths: paths)
            }
            guard record.retirementIdentity?.matches(retired) == true || (record.phase == .deleting && !FileManager.default.fileExists(atPath: retired.path)) else { throw RuriError.message("原文件清理目录身份改变。") }
            if record.phase != .deleting {
                progress(.init(phase: .retiring))
                for source in record.sources {
                    let location = try record.source(source.part, paths: paths), target = retired.appendingPathComponent(source.part.rawValue)
                    let receipt = try FileTreeManifest.load(from: root.appendingPathComponent("source-" + source.part.rawValue + ".json"), expectedDigest: source.digest)
                    if FileManager.default.fileExists(atPath: location.path) {
                        guard source.identity.matches(location), !FileManager.default.fileExists(atPath: target.path) else { throw RuriError.message("原位置出现其他文件，未继续清理。") }
                        try receipt.requireMatch(in: location)
                        guard rename(location.path, target.path) == 0 else { throw RuriError.message("无法整理原实例文件，请恢复移动。") }
                    }
                    guard source.identity.matches(target) else { throw RuriError.message("无法确认原文件的清理位置。") }
                    try receipt.requireMatch(in: target)
                }
                try verifyRepositoryDestination(record, paths: paths)
                record.phase = .deleting; try record.save(paths: paths)
            }
            progress(.init(phase: .deleting))
            for source in record.sources {
                let target = retired.appendingPathComponent(source.part.rawValue)
                if FileManager.default.fileExists(atPath: target.path) {
                    guard source.identity.matches(target) else { throw RuriError.message("剩余原文件的身份改变。") }
                    try FileTreeManifest.load(from: root.appendingPathComponent("source-" + source.part.rawValue + ".json"), expectedDigest: source.digest).requireRemainingMatch(in: target)
                    try FileManager.default.removeItem(at: target)
                }
            }
            if FileManager.default.fileExists(atPath: retired.path), rmdir(retired.path) != 0 { kept.append(retired) }
        }
        try record.clearReservations()
        let workspace = try record.workspace(paths: paths)
        if record.workspaceIdentity?.matches(workspace) == true { do { try FileManager.default.removeItem(at: workspace) } catch { kept.append(workspace) } }
        let recordLocation = try retireRepositoryRecord(record)
        if kept.isEmpty { try? FileManager.default.removeItem(at: recordLocation) }
        return .init(state: state, preservedFiles: kept, warning: kept.isEmpty ? nil : "实例已移动，部分原文件或工作文件保留，可在 Finder 中检查。")
    }
    private func abandonRepository(_ input: RepositoryMoveJournal, paths: LauncherPaths) throws -> [URL] {
        var record = input; try record.validateLocations(paths: paths)
        guard record.retirementIdentity == nil else { throw RuriError.message("移动包含原文件清理记录，需要先核对提交状态。") }
        record.phase = .recovering; try record.save(paths: paths)
        let workspace = try record.workspace(paths: paths)
        var kept: [URL] = []
        for publication in record.publications {
            let target = try record.destination(publication.part, paths: paths)
            if (publication.published ?? publication.staged).matches(target) {
                guard record.workspaceIdentity?.matches(workspace) == true else { throw RuriError.message("工作区身份改变，目标文件原地保留。") }
                try RunDirectoryFileCopy.returnToWorkspace(target, workspace: workspace)
            } else if FileManager.default.fileExists(atPath: target.path) { kept.append(target) }
        }
        try record.clearReservations()
        if record.workspaceIdentity?.matches(workspace) == true {
            let folder = try LauncherPaths.safePath(".ruri/move-recovery/" + record.id.uuidString, within: record.targetCollection?.url ?? paths.root)
            try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try RunDirectoryFileCopy.moveWithoutReplacing(workspace, to: folder); kept.append(folder)
        }
        let retired = try retireRepositoryRecord(record)
        if kept.isEmpty { kept.append(retired) }
        return kept
    }
    private func retireRepositoryRecord(_ record: RepositoryMoveJournal) throws -> URL {
        let target = try LauncherPaths.safePath("instance-move-recovery/\(record.original.id.uuidString)-\(record.id.uuidString)", within: paths.root)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RunDirectoryFileCopy.moveWithoutReplacing(InstanceMoveJournal.root(paths: paths, instanceID: record.original.id), to: target)
        return target
    }
}
