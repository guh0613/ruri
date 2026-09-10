import Foundation

struct RepositoryMoveSnapshot: Sendable {
    let installation: MinecraftInstallationCopy
    let installationReceipt: FileTreeManifest
    let sourceVersion: FileTreeManifest?
    let sourceVersionIdentity: RunDirectoryCopyJournal.Identity?

    static func capture(source: GameInstance, moved: GameInstance, paths: LauncherPaths, id: UUID, installation: MinecraftInstallationCopy) throws -> (InstanceMoveSnapshot, Self) {
        let metadata = paths.instance(source.id), sourceFiles = try FileTree.entries(in: metadata, ignoringTransientFiles: false)
        let original = try FileTreeManifest.capture(sourceFiles, rootAttributes: FileExtendedAttributes.capture(metadata))
        let targetRepository = moved.repositoryVersionID != nil
        let gamePrefix = targetRepository ? "version" : "metadata/minecraft"
        let previous = "metadata/" + InstanceMoveSnapshot.previousDataPath(id)
        func mapped(_ file: FileTree.Entry, _ path: String) -> FileTree.Entry { .init(url: file.url, path: path, directory: file.directory, size: file.size, modified: file.modified) }
        func rootEntry(_ root: URL, _ path: String) throws -> FileTree.Entry {
            .init(url: root, path: path, directory: true, size: 0, modified: try root.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast)
        }
        var files = [try rootEntry(metadata, "metadata")], hasPrevious = false
        for file in sourceFiles {
            let top = String(file.path.split(separator: "/")[0])
            if source.repositoryVersionID == nil, source.runDirectory != .custom, source.runDirectory != .shared, top == "minecraft" {
                files.append(mapped(file, gamePrefix + String(file.path.dropFirst("minecraft".count))))
            } else if (source.runDirectory == .shared && ["minecraft", "content.json", "world-backups"].contains(top)) ||
                      (!targetRepository && ["version.json", "installation"].contains(top)) {
                files.append(mapped(file, previous + "/metadata/" + file.path)); hasPrevious = true
            } else { files.append(mapped(file, "metadata/" + file.path)) }
        }
        var versionReceipt: FileTreeManifest?, versionIdentity: RunDirectoryCopyJournal.Identity?
        if source.repositoryVersionID != nil {
            let root = paths.versionDirectory(source.id)
            versionIdentity = try .read(root)
            let raw = try FileTree.entries(in: root, ignoringTransientFiles: false)
            versionReceipt = try FileTreeManifest.capture(raw, rootAttributes: FileExtendedAttributes.capture(root))
            if source.runDirectory == .isolated || source.runDirectory == nil {
                files.append(try rootEntry(root, gamePrefix))
                let reserved = Set(MinecraftGameDataFiles.reservedNames(paths: paths, instanceID: source.id).map(MinecraftGameDataFiles.key))
                for file in raw {
                    let top = MinecraftGameDataFiles.key(String(file.path.split(separator: "/")[0]))
                    files.append(mapped(file, (reserved.contains(top) ? previous + "/version/" : gamePrefix + "/") + file.path))
                    if reserved.contains(top) { hasPrevious = true }
                }
            } else {
                files.append(try rootEntry(root, previous + "/version"))
                files += raw.map { mapped($0, previous + "/version/" + $0.path) }; hasPrevious = true
            }
        }
        if source.runDirectory == .shared {
            let game = paths.game(source.id)
            let excluded = MinecraftGameDataFiles.reservedNames(paths: paths, instanceID: source.id).union([".ruri"])
            files.append(try rootEntry(game, gamePrefix))
            files += try FileTree.entries(in: game, excluding: excluded, ignoringTransientFiles: false).map { mapped($0, gamePrefix + "/" + $0.path) }
            files += try FileTree.entries(in: paths.gameDataState(source.id), ignoringTransientFiles: false).filter {
                ["content.json", "world-backups"].contains(String($0.path.split(separator: "/")[0]))
            }.map { mapped($0, "metadata/" + $0.path) }
        }
        let required: Set<String> = targetRepository ? ["metadata", "version"] : ["metadata"]
        let destination = try FileTreeManifest.capture(files, requiringDirectories: required)
        let inputs = try FileTreeManifest.capture(installation.inputs)
        return (.init(entries: files, original: original, destination: destination, hasPreviousData: hasPrevious),
                .init(installation: installation, installationReceipt: inputs, sourceVersion: versionReceipt, sourceVersionIdentity: versionIdentity))
    }
}

extension InstanceMover {
    func repositoryPreview(source: GameInstance, directoryID: UUID, paths: LauncherPaths) async throws -> InstanceMovePreview {
        guard source.installed else { throw RuriError.message("请先安装实例，再移动到 Minecraft 文件夹。") }
        guard paths.directoryID(for: source.id) != directoryID else { throw RuriError.message("实例已位于所选文件夹中。") }
        guard directoryID == GameDirectory.defaultID || paths.directories.contains(where: { $0.id == directoryID }) else { throw RuriError.message("找不到目标文件夹。") }
        let access = try await InstanceMoveAccess.acquire(instance: source, paths: paths)
        defer { withExtendedLifetime(access) {} }
        try requireIndependentVersion(source, paths: paths)
        let id = UUID()
        var moved = source; moved.directoryID = directoryID; moved.lastInstanceMoveID = id
        if source.runDirectory == .shared { moved.runDirectory = .isolated; moved.customRunDirectory = nil; moved.lastRunDirectoryChangeID = nil }
        if paths.isMinecraftDirectory(directoryID) {
            moved.name = source.repositoryVersionID ?? source.name
            moved = try MinecraftFolderStore.preparingNewInstance(moved, paths: paths)
            moved.name = source.name; moved.repositoryComponents = source.repositoryComponents ?? source.importedInstallation?.components
            moved.importedInstallation = nil; moved.repositoryIssue = nil
        } else {
            moved.importedInstallation = .init(sourceVersionID: source.repositoryVersionID!, components: source.repositoryComponents ?? [])
            moved.repositoryVersionID = nil; moved.repositoryComponents = nil; moved.repositoryIssue = nil
        }
        moved.packLibraries = nil
        let target = paths.including(moved)
        try target.validateInstanceLocation(moved.id)
        try Self.requireAbsent(target.instance(moved.id))
        if moved.repositoryVersionID != nil { try Self.requireAbsent(target.versionDirectory(moved.id)) }
        let targetRoot = target.directoryRoot(directoryID).standardizedFileURL.resolvingSymlinksInPath().path
        for sourceRoot in [paths.instance(source.id), paths.game(source.id)] {
            let root = sourceRoot.standardizedFileURL.resolvingSymlinksInPath().path
            guard !targetRoot.hasPrefix(root + "/"), targetRoot != root else { throw RuriError.message("目标文件夹不能位于源实例或运行目录里面。") }
        }
        let installation = try MinecraftInstallationCopy.read(instance: source, copy: moved, paths: paths, portable: true)
        func rewrite(_ value: String) throws -> String {
            let before = try ArgumentTokenizer.split(value), after = before.map { MinecraftInstallationCopy.rewrite($0, replacements: installation.replacements) }
            return before == after ? value : ArgumentTokenizer.join(after)
        }
        moved.extraJVMArguments = try rewrite(moved.extraJVMArguments); moved.extraGameArguments = try moved.extraGameArguments.map(rewrite)
        if var overrides = moved.launchOverrides {
            overrides.jvmArguments = try overrides.jvmArguments.map(rewrite); overrides.gameArguments = try overrides.gameArguments.map(rewrite); moved.launchOverrides = overrides
        }
        let identity = try RunDirectoryCopyJournal.Identity.read(paths.instance(source.id))
        let (snapshot, repository) = try RepositoryMoveSnapshot.capture(source: source, moved: moved, paths: paths, id: id, installation: installation)
        func collection(_ id: UUID) -> GameDirectory? { var item = paths.directories.first { $0.id == id }; item?.bookmark = nil; return item }
        return .init(id: id, source: source, moved: moved, sourceDirectory: paths.instance(source.id), destination: target.instance(source.id),
                     sourceGame: paths.game(source.id), destinationGame: target.game(source.id),
                     sourceCollection: collection(paths.directoryID(for: source.id)), targetCollection: collection(directoryID), sourceIdentity: identity,
                     snapshot: snapshot, repository: repository)
    }

    func requireRepositoryUnchanged(_ preview: InstanceMovePreview, paths: LauncherPaths) throws {
        guard let repository = preview.repository, preview.sourceIdentity.matches(paths.instance(preview.source.id)) else { throw RuriError.message("源实例目录身份改变，请重新预览。") }
        if let identity = repository.sourceVersionIdentity, !identity.matches(paths.versionDirectory(preview.source.id)) { throw RuriError.message("源版本文件夹已被替换，请重新预览。") }
        let (snapshot, current) = try RepositoryMoveSnapshot.capture(source: preview.source, moved: preview.moved, paths: paths, id: preview.id, installation: repository.installation)
        guard snapshot.original == preview.snapshot.original, snapshot.destination == preview.snapshot.destination, snapshot.entries == preview.snapshot.entries,
              current.sourceVersion == repository.sourceVersion, current.installationReceipt == repository.installationReceipt else {
            throw RuriError.message("源文件在预览后改变，请刷新移动预览。")
        }
    }

    func requireIndependentVersion(_ source: GameInstance, paths: LauncherPaths) throws {
        guard let version = source.repositoryVersionID else { return }
        let versionRoot = paths.versionDirectory(source.id).standardizedFileURL.resolvingSymlinksInPath().path
        func inside(_ url: URL) -> Bool { let path = url.standardizedFileURL.resolvingSymlinksInPath().path; return path == versionRoot || path.hasPrefix(versionRoot + "/") }
        let state = try StateStore.load(paths)
        for other in state.instances where other.id != source.id && inside(paths.game(other.id)) {
            throw RuriError.message("“\(other.name)”仍将此版本目录用作运行目录，请先调整它的运行目录。")
        }
        let reader = MinecraftDirectoryReader(), root = paths.directoryRoot(paths.directoryID(for: source.id))
        let catalog = try reader.scanNow(root, allowEmpty: true)
        for other in catalog.versions where other.id != version {
            if let resolution = try? reader.resolveManifestNow(other, in: catalog) {
                var dependent = inside(resolution.clientFile) || resolution.sourceManifests.contains { inside($0.url) } || resolution.libraries.contains { $0.localFile.map(inside) == true }
                let resources = try paths.resources(for: source)
                for library in resolution.manifest.libraries {
                    for artifact in [try library.artifact()].compactMap({ $0 }) + Array(library.downloads?.classifiers?.values ?? [:].values) {
                        if let file = try? resources.libraryFile(artifact, fallback: Library.mavenPath(library.name)), inside(file) { dependent = true }
                    }
                }
                if dependent { throw RuriError.message("“\(other.id)”仍依赖此版本的清单或游戏文件。请先移动依赖它的版本，或使用复制实例。") }
            } else if let data = try? RunDirectoryCopyGuard.read(other.directory.appendingPathComponent(other.id + ".json"), limit: 8_388_608),
                      let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      [try? MinecraftDirectoryScan.identifier(raw["inheritsFrom"]), try? MinecraftDirectoryScan.identifier(raw["jar"])].contains(version) {
                throw RuriError.message("“\(other.id)”仍引用此版本，请先处理该版本。")
            }
        }
    }
}
