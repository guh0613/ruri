import RuriLocalization
import Foundation
import Darwin
import os

extension InstanceCopier {
    func repositoryPreview(original: GameInstance, copy input: GameInstance, id: UUID, collection: GameDirectory,
                           paths: LauncherPaths, options: InstanceCopyOptions) async throws -> InstanceCopyPreview {
        guard original.installed else { throw RuriError.message(Messages.CoreRepositoryInstanceCopy.sourceInstallationRequired) }
        let access = try await acquire(original, paths: paths); defer { withExtendedLifetime(access) {} }
        var copy = try MinecraftFolderStore.preparingNewInstance(input, paths: paths)
        copy.repositoryComponents = original.repositoryComponents ?? original.importedInstallation?.components
        copy.importedInstallation = nil; copy.repositoryIssue = nil; copy.packLibraries = nil
        let installation = try MinecraftInstallationCopy.read(instance: original, copy: copy, paths: paths)
        func rewrite(_ arguments: String) throws -> String {
            let original = try ArgumentTokenizer.split(arguments)
            let rewritten = original.map { MinecraftInstallationCopy.rewrite($0, replacements: installation.replacements) }
            return original == rewritten ? arguments : ArgumentTokenizer.join(rewritten)
        }
        copy.extraJVMArguments = try rewrite(copy.extraJVMArguments)
        copy.extraGameArguments = try copy.extraGameArguments.map(rewrite)
        if var overrides = copy.launchOverrides {
            overrides.jvmArguments = try overrides.jvmArguments.map(rewrite)
            overrides.gameArguments = try overrides.gameArguments.map(rewrite)
            copy.launchOverrides = overrides
        }
        try InstanceTransfer.validate(copy)
        let entries = try repositoryEntries(original, copy: copy, paths: paths, options: options)
        let manifest = try FileTreeManifest.capture(entries, requiringDirectories: ["version", "metadata"])
        guard try repositoryEntries(original, copy: copy, paths: paths, options: options) == entries else { throw RuriError.message(Messages.CoreRepositoryInstanceCopy.sourceManifestChangedDuringPreview) }
        return .init(id: id, source: original, copy: copy, sourceGame: paths.game(original.id), destination: paths.including(copy).versionDirectory(copy.id),
                     options: options, targetCollection: collection, entries: entries, manifest: manifest, installation: installation)
    }

    func copyToRepository(_ preview: InstanceCopyPreview, progress: @Sendable (RunDirectoryCopyProgress) -> Void) async throws -> RunDirectoryCopyResult {
        guard let installation = preview.installation else { throw RuriError.message(Messages.CoreRepositoryInstanceCopy.installationFilesMissing) }
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        try validateRepositoryPreview(preview, state: state)
        let access = try await acquire(preview.source, paths: current); defer { withExtendedLifetime(access) {} }
        progress(.init(phase: .verifying, completed: 0, total: 0, bytesCopied: 0, totalBytes: preview.bytes))
        try validateRepositoryFiles(preview, paths: current)
        let owner = InstanceCopyOwner(transactionID: preview.id, sourceID: preview.source.id, copyID: preview.copy.id,
                                      sourceName: preview.source.name, copyName: preview.copy.name)
        let transaction = try RepositoryImportTransaction(instance: preview.copy, paths: current, copySource: owner)
        let staging = transaction.staging
        do {
            @Sendable func validateLocations() throws {
                try current.validateInstanceLocation(preview.source.id)
                try preview.targetCollection?.validateAvailability()
            }
            let counters = OSAllocatedUnfairLock(initialState: (bytes: Int64(0), completed: 0, last: Date.distantPast))
            @Sendable func report(_ amount: Int64, finished: Bool = false) {
                let update: RunDirectoryCopyProgress? = counters.withLock { value in
                    value.bytes += amount; if finished { value.completed += 1 }
                    guard value.completed == preview.fileCount || Date().timeIntervalSince(value.last) >= 0.1 else { return nil }
                    value.last = Date()
                    return .init(phase: .copying, completed: value.completed, total: preview.fileCount, bytesCopied: value.bytes, totalBytes: preview.bytes)
                }
                if let update { progress(update) }
            }
            try RunDirectoryFileCopy.entries(preview.entries, to: transaction.workspace, validate: validateLocations) { report($0, finished: $1) }
            for folder in [staging.instance(preview.copy.id), staging.versionDirectory(preview.copy.id)] {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            try preview.manifest.requireMatch(in: transaction.workspace, excluding: ["transaction.json", ".operation.lock"], ignoringTransientFiles: true)
            let client = staging.versionDirectory(preview.copy.id).appendingPathComponent(installation.client.path)
            try RunDirectoryFileCopy.file(installation.client.source, to: client, validate: validateLocations) { report($0) }
            try MinecraftInstallationFiles.requireResource(client, sha1: installation.client.sha1, size: installation.client.size)
            report(0, finished: true)
            let targetRoot = current.directoryRoot(preview.copy.directoryID!)
            for resource in installation.resources {
                try await MinecraftInstallationFiles.copyResource(resource, root: targetRoot, validate: validateLocations) { report($0) }
                report(0, finished: true)
            }
            for (path, data) in installation.generatedResources.sorted(by: { $0.key < $1.key }) {
                // Generated indices use content-derived names and the same cache
                // lock/publication path as existing resource files.
                let temporary = transaction.workspace.appendingPathComponent("resource-" + UUID().uuidString)
                try data.write(to: temporary, options: .withoutOverwriting)
                defer { try? FileManager.default.removeItem(at: temporary) }
                let resource = MinecraftInstallationCopy.Resource(source: temporary, path: path, sha1: MinecraftInstallationCopy.sha1(data), size: Int64(data.count))
                try await MinecraftInstallationFiles.copyResource(resource, root: targetRoot, validate: validateLocations) { report($0) }
                report(0, finished: true)
            }
            for (path, data) in installation.sourceManifests {
                let file = try LauncherPaths.safePath(path, within: staging.instance(preview.copy.id))
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .withoutOverwriting); report(Int64(data.count), finished: true)
            }
            try installation.manifest.write(to: staging.manifest(preview.copy.id), options: .withoutOverwriting)
            report(Int64(installation.manifest.count), finished: true)
            try rebindRepositoryModpack(staging, copy: preview.copy)
            try Task.checkCancellation()
            progress(.init(phase: .verifying, completed: 0, total: 0, bytesCopied: preview.bytes, totalBytes: preview.bytes))
            try validateRepositoryPreview(preview, state: StateStore.load(paths))
            try validateRepositoryFiles(preview, paths: current)
            progress(.init(phase: .publishing, completed: 0, total: 1, bytesCopied: preview.bytes, totalBytes: preview.bytes))
            _ = try transaction.publish(preview.copy)
            progress(.init(phase: .committed, completed: 1, total: 1, bytesCopied: preview.bytes, totalBytes: preview.bytes))
            return .init(state: try StateStore.load(paths), preservedCopy: nil, warning: nil)
        } catch {
            let cancelled = Task.isCancelled || error is CancellationError
            if let latest = try? StateStore.load(paths), latest.instances.first(where: { $0.id == preview.copy.id })?.lastInstanceCopyID == preview.id {
                return .init(state: latest, preservedCopy: transaction.workspace, warning: Messages.CoreRepositoryInstanceCopy.copyCleanupPending.localized)
            }
            let reason = cancelled ? Messages.CoreRepositoryInstanceCopy.copyCancelled.localized : Messages.CoreRepositoryInstanceCopy.copyIncomplete(error.localizedDescription).localized
            do {
                let kept = try transaction.preserve()
                throw RunDirectoryCopyFailure(message: reason, preservedCopy: kept, cancelled: cancelled)
            } catch let failure as RunDirectoryCopyFailure { throw failure }
            catch { throw RunDirectoryCopyFailure(message: Messages.CoreRepositoryInstanceCopy.recoveryFailure(reason, error.localizedDescription).localized, preservedCopy: transaction.workspace, cancelled: cancelled) }
        }
    }

    func repositoryPending(instanceID: UUID, state: PersistentState) throws -> (recovery: RepositoryImportRecovery, directory: GameDirectory)? {
        for directory in state.gameDirectories ?? [] where directory.isMinecraft {
            // Disconnected unrelated folders must not prevent copying this instance.
            guard (try? directory.validateAvailability()) != nil else { continue }
            if let recovery = try RepositoryImportStore.pending(directoryID: directory.id, paths: paths).first(where: {
                $0.copySource?.sourceID == instanceID || $0.copySource?.copyID == instanceID
            }) { return (recovery, directory) }
        }
        return nil
    }

    private func validateRepositoryPreview(_ preview: InstanceCopyPreview, state: PersistentState) throws {
        guard state.instances.first(where: { $0.id == preview.source.id }) == preview.source,
              !state.instances.contains(where: { $0.id == preview.copy.id }), let target = preview.targetCollection,
              let actual = state.gameDirectories?.first(where: { $0.id == target.id }), actual.isMinecraft,
              actual.url.standardizedFileURL == target.url.standardizedFileURL else { throw RuriError.message(Messages.CoreRepositoryInstanceCopy.sourceOrTargetChanged) }
        try target.validateAvailability()
    }
    private func validateRepositoryFiles(_ preview: InstanceCopyPreview, paths: LauncherPaths) throws {
        let entries = try repositoryEntries(preview.source, copy: preview.copy, paths: paths, options: preview.options)
        guard entries == preview.entries,
              try FileTreeManifest.capture(entries, requiringDirectories: ["version", "metadata"]) == preview.manifest,
              try MinecraftInstallationCopy.read(instance: preview.source, copy: preview.copy, paths: paths) == preview.installation else {
            throw RuriError.message(Messages.CoreRepositoryInstanceCopy.sourceFilesChanged)
        }
    }
    private func repositoryEntries(_ source: GameInstance, copy: GameInstance, paths: LauncherPaths, options: InstanceCopyOptions) throws -> [FileTree.Entry] {
        let game = paths.game(source.id), target = paths.including(copy).versionDirectory(copy.id)
        let sourcePath = game.standardizedFileURL.resolvingSymlinksInPath().path, targetPath = target.standardizedFileURL.resolvingSymlinksInPath().path
        if targetPath.hasPrefix(sourcePath + "/") {
            guard source.repositoryVersionID != nil, MinecraftGameDataFiles.sameLocation(game, paths.directoryRoot(paths.directoryID(for: source.id))),
                  MinecraftGameDataFiles.sameLocation(paths.directoryRoot(paths.directoryID(for: source.id)), paths.directoryRoot(copy.directoryID!)) else {
                throw RuriError.message(Messages.CoreRepositoryInstanceCopy.targetInsideSourceContent)
            }
        }
        let pack = try ModpackRegistry.load(paths: paths, instanceID: source.id)
        var excluded = try InstanceTransfer.exclusions(game, includeWorlds: options.includeWorlds)
        let declared = Set((pack?.files ?? []).compactMap { $0.path.split(separator: "/").first.map(String.init) })
        excluded.subtract(declared)
        excluded.formUnion(MinecraftGameDataFiles.reservedNames(paths: paths, instanceID: source.id))
        excluded.insert(".ruri"); if !options.includeWorlds { excluded.insert("saves") }
        var result: [FileTree.Entry] = []
        if FileManager.default.fileExists(atPath: game.path) {
            let files = try FileTree.entries(in: game, excluding: excluded)
            let reserved = Set(MinecraftGameDataFiles.reservedNames(paths: paths.including(copy), instanceID: copy.id).map(MinecraftGameDataFiles.key))
            if let conflict = files.first(where: { reserved.contains(MinecraftGameDataFiles.key(String($0.path.split(separator: "/").first!))) }) {
                throw RuriError.message(Messages.CoreRepositoryInstanceCopy.installationFilenameConflict(conflict.path))
            }
            result += files.map { .init(url: $0.url, path: "version/" + $0.path, directory: $0.directory, size: $0.size, modified: $0.modified) }
        }
        for name in ["natives", "source-mcbbs.packmeta", "modpack-state.json", "content.json"] + (options.includeBackups ? ["world-backups"] : []) {
            let root = ["content.json", "world-backups"].contains(name) ? paths.gameDataState(source.id) : paths.instance(source.id)
            let file = try LauncherPaths.safePath(name, within: root)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let info = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
            guard info.isSymbolicLink != true, info.isDirectory == true || info.isRegularFile == true else { throw RuriError.message(Messages.CoreRepositoryInstanceCopy.unsupportedInstanceFiles(name)) }
            result.append(.init(url: file, path: "metadata/" + name, directory: info.isDirectory == true, size: info.isDirectory == true ? 0 : Int64(info.fileSize ?? 0), modified: info.contentModificationDate ?? .distantPast))
            if info.isDirectory == true { result += try FileTree.entries(in: file).map { .init(url: $0.url, path: "metadata/" + name + "/" + $0.path, directory: $0.directory, size: $0.size, modified: $0.modified) } }
        }
        return result
    }
    private func rebindRepositoryModpack(_ paths: LauncherPaths, copy: GameInstance) throws {
        let file = paths.instance(copy.id).appendingPathComponent("modpack-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        var record = try ModpackRegistry.read(file, game: paths.game(copy.id))
        record.settings = copy
        try FileExtendedAttributes.rewrite(JSONEncoder().encode(record), at: file)
    }
}
