import RuriLocalization
import Foundation

/// Registers a repository in place. Discovery reads version descriptions only;
/// game files are resolved from the repository when an instance is launched.
public enum MinecraftFolderStore {
    @discardableResult public static func add(name: String, url: URL, paths: LauncherPaths) throws -> PersistentState {
        try attach(name: name, url: url, restoring: nil, paths: paths)
    }

    @discardableResult public static func restore(_ id: UUID, from url: URL, paths: LauncherPaths) throws -> PersistentState {
        try attach(name: url.lastPathComponent, url: url, restoring: id, paths: paths)
    }

    private static func attach(name: String, url: URL, restoring id: UUID?, paths: LauncherPaths) throws -> PersistentState {
        let catalog = try MinecraftDirectoryReader().scanNow(url, allowEmpty: true)
        return try StateStore.update(paths) { state in
            if let id {
                guard let retained = state.detachedMinecraftFolders?.first(where: { $0.id == id }) else {
                    throw RuriError.message(Messages.CoreMinecraftFolderStore.folderListChanged)
                }
                var candidate = retained.directory; candidate.url = catalog.directory
                try candidate.validateAvailability()
            }
            if let existing = state.gameDirectories?.first(where: { $0.url.standardizedFileURL.resolvingSymlinksInPath() == catalog.directory }) {
                guard existing.isMinecraft else { throw RuriError.message(Messages.CoreMinecraftFolderStore.alreadyAddedFolder) }
                try existing.validateAvailability()
                state.selectedDirectoryID = existing.id
                try synchronize(catalog, directory: existing, state: &state, paths: paths)
                return
            }
            var directory = GameDirectory(id: UUID(), name: try GameDirectory.validName(name), url: catalog.directory, bookmark: nil, createdAt: Date(), layout: .minecraft)
            try paths.configured(with: state).checkNewDirectory(directory)
            let markerFile = directory.url.appendingPathComponent(GameDirectory.markerName)
            if FileManager.default.fileExists(atPath: markerFile.path) {
                let info = try markerFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? .max) <= 1024 else { throw RuriError.message(Messages.CoreMinecraftFolderStore.invalidRuriMarker) }
                let marker = try JSONDecoder().decode(GameDirectory.Marker.self, from: Data(contentsOf: markerFile))
                guard marker.schema == 1, marker.layout == .minecraft, marker.id != GameDirectory.defaultID,
                      state.gameDirectories?.contains(where: { $0.id == marker.id }) != true else { throw RuriError.message(Messages.CoreMinecraftFolderStore.duplicateFolder) }
                directory = GameDirectory(id: marker.id, name: directory.name, url: directory.url, bookmark: nil, createdAt: directory.createdAt, layout: .minecraft)
            } else {
                try JSONEncoder().encode(GameDirectory.Marker(schema: 1, id: directory.id, layout: .minecraft)).write(to: markerFile, options: .withoutOverwriting)
            }
            let detached = state.detachedMinecraftFolders?.first { $0.id == directory.id }
            if let detached {
                let original = detached.directory
                let located = original.resolvingBookmark()
                if located.url.standardizedFileURL.resolvingSymlinksInPath().path != directory.url.path,
                   (try? located.validateAvailability()) != nil {
                    throw RuriError.message(Messages.CoreMinecraftFolderStore.originalFolderAvailable)
                }
                directory = GameDirectory(id: original.id, name: id == nil ? directory.name : original.name, url: directory.url, bookmark: nil, createdAt: original.createdAt, layout: .minecraft)
                state.instances.append(contentsOf: detached.instances)
                state.detachedMinecraftFolders?.removeAll { $0.id == directory.id }
                state.selectedInstanceID = detached.selectedInstanceID
            }
            directory.bookmark = try directory.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            state.gameDirectories = (state.gameDirectories ?? []) + [directory]
            state.selectedDirectoryID = directory.id
            try synchronize(catalog, directory: directory, state: &state, paths: paths)
        }
    }

    @discardableResult public static func refresh(_ id: UUID, paths: LauncherPaths) throws -> PersistentState {
        let initial = try StateStore.load(paths)
        guard let directory = initial.gameDirectories?.first(where: { $0.id == id }), directory.isMinecraft else { return initial }
        try directory.validateAvailability()
        let catalog = try MinecraftDirectoryReader().scanNow(directory.url, allowEmpty: true)
        return try StateStore.update(paths) { state in
            guard state.gameDirectories?.first(where: { $0.id == id }) == directory else { throw RuriError.message(Messages.CoreMinecraftFolderStore.locationChanged) }
            try synchronize(catalog, directory: directory, state: &state, paths: paths)
        }
    }

    private static func synchronize(_ catalog: MinecraftDirectoryCatalog, directory: GameDirectory, state: inout PersistentState, paths: LauncherPaths) throws {
        let reserved = try RepositoryImportStore.reservedVersionNames(in: directory.url).union(RepositoryMoveReservation.names(in: directory.url))
        for version in catalog.versions {
            guard !reserved.contains(MinecraftGameDataFiles.key(version.id)), FileManager.default.fileExists(atPath: version.directory.path) else { continue }
            let index = state.instances.firstIndex { $0.directoryID == directory.id && $0.repositoryVersionID == version.id }
            if let index, ModpackUpdateStore.hasPending(paths: paths.configured(with: state), instanceID: state.instances[index].id) { continue }
            if let index, InstanceMoveGuard.hasPending(paths: paths, instanceID: state.instances[index].id) { continue }
            var item = index.map { state.instances[$0] } ?? GameInstance(name: version.id, gameVersion: version.gameVersion ?? version.id)
            item.directoryID = directory.id; item.repositoryVersionID = version.id
            item.repositoryComponents = version.components; item.repositoryIssue = version.issue
            item.gameVersion = version.gameVersion ?? item.gameVersion
            let component = version.components.first { component in LoaderKind.allCases.contains { $0 != .vanilla && $0.title == component.name } }
            item.loader = component.flatMap { component in LoaderKind.allCases.first { $0.title == component.name } } ?? .vanilla
            item.loaderVersion = component?.version
            item.installed = true
            if index == nil {
                item.launchOverrides = .init()
                let isolated = version.gameLocations.first { $0.directory == version.directory }
                let target = version.suggestedLocationID.map { URL(fileURLWithPath: $0, isDirectory: true) }
                    ?? (isolated?.contents.isEmpty == false ? version.directory : directory.url)
                if target.standardizedFileURL == directory.url.standardizedFileURL { item.runDirectory = .shared }
                else if target.standardizedFileURL == version.directory.standardizedFileURL { item.runDirectory = .isolated }
                else {
                    item.runDirectory = .custom
                    // Failure stays visible instead of silently opening another set of saves.
                    do { item.customRunDirectory = try CustomRunDirectory.register(at: target, paths: paths.configured(with: state)) }
                    catch { throw RuriError.message(Messages.CoreMinecraftFolderStore.customDirectoryUnavailable(String(describing: version.id), error.localizedDescription)) }
                }
            }
            if let index { state.instances[index] = item } else { state.instances.append(item) }
        }
        let found = Set(catalog.versions.map(\.id))
        for index in state.instances.indices where state.instances[index].directoryID == directory.id {
            if let version = state.instances[index].repositoryVersionID, !found.contains(version), state.instances[index].installed,
               !reserved.contains(MinecraftGameDataFiles.key(version)), !InstanceMoveGuard.hasPending(paths: paths, instanceID: state.instances[index].id) {
                let current = paths.configured(with: state)
                state.instances[index].repositoryIssue = FileManager.default.fileExists(atPath: current.repositoryImportWorkspace(state.instances[index].id).path)
                    ? Messages.CoreMinecraftFolderStore.pendingWorkFiles.localized
                    : Messages.CoreMinecraftFolderStore.versionDirectoryMissing.localized
            }
        }
        if state.selectedDirectoryID == directory.id, !state.instances.contains(where: { $0.id == state.selectedInstanceID && $0.directoryID == directory.id }) {
            state.selectedInstanceID = state.instances.first(where: { $0.directoryID == directory.id && $0.repositoryIssue == nil })?.id
        }
    }

    /// Version deletion affects only that version folder. Shared libraries,
    /// assets and game data remain in place, including other profiles’ base jars.
    @discardableResult public static func trashVersion(_ id: UUID, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { state in
            guard let instance = state.instances.first(where: { $0.id == id }), let versionID = instance.repositoryVersionID else { throw RuriError.message(Messages.CoreMinecraftFolderStore.localVersionMissing) }
            let current = paths.configured(with: state)
            let lease = try GameRunLease.acquire(paths: current, instanceID: id)
            defer { withExtendedLifetime(lease) {} }
            let folder = current.versionDirectory(id)
            if FileManager.default.fileExists(atPath: folder.path) {
                let root = current.directoryRoot(current.directoryID(for: id)), reader = MinecraftDirectoryReader()
                let catalog = try reader.scanNow(root, allowEmpty: true)
                for other in catalog.versions where other.id != versionID {
                    guard other.issue == nil else { throw RuriError.message(Messages.CoreMinecraftFolderStore.dependencyCheckRequired(String(describing: other.id))) }
                    let resolved = try reader.resolveManifestNow(other, in: catalog)
                    if resolved.manifest.jar == versionID || resolved.sourceManifests.contains(where: { $0.url == current.manifest(id) }) {
                        throw RuriError.message(Messages.CoreMinecraftFolderStore.dependencyExists(String(describing: other.id)))
                    }
                }
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            }
            // History remains recoverable under .ruri; removing the instance
            // never moves a shared or custom game root to the Trash.
            state.instances.removeAll { $0.id == id }
            if state.selectedInstanceID == id { state.selectedInstanceID = state.instances.first(where: { $0.directoryID == instance.directoryID })?.id }
        }
    }

    /// Bind a new installation before any file is written. Existing profiles
    /// must never be replaced just because their display names happen to match.
    public static func preparingNewInstance(_ input: GameInstance, paths: LauncherPaths) throws -> GameInstance {
        guard paths.isMinecraftDirectory(input.directoryID ?? paths.newInstanceDirectoryID) else { return input }
        var item = input
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        try MinecraftDirectoryScan.checkIdentifier(name)
        let root = paths.directoryRoot(input.directoryID ?? paths.newInstanceDirectoryID)
        if let directory = paths.directories.first(where: { $0.id == (input.directoryID ?? paths.newInstanceDirectoryID) }) {
            try RepositoryImportStore.requireNameAvailable(name, directory: directory, paths: paths)
        }
        let file = try LauncherPaths.safePath("versions/\(name)", within: root)
        let state = try StateStore.load(paths)
        guard !FileManager.default.fileExists(atPath: file.path), !state.instances.contains(where: {
            ($0.directoryID ?? GameDirectory.defaultID) == (input.directoryID ?? paths.newInstanceDirectoryID) && $0.repositoryVersionID?.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { throw RuriError.message(Messages.CoreMinecraftFolderStore.duplicateVersion(name)) }
        item.repositoryVersionID = name
        return item
    }
}
