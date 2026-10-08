import Foundation
import RuriLocalization

package protocol SessionLocationPaths: SessionPaths {
    var directories: [GameDirectory] { get }
    var instanceDirectories: [UUID: UUID] { get }
    var newInstanceDirectoryID: UUID { get }
    var instanceRunDirectories: [UUID: GameRunDirectory]? { get }
    var instanceCustomDirectories: [UUID: CustomRunDirectory]? { get }
    var instanceRepositoryVersions: [UUID: String]? { get }
    var repositoryImportID: UUID? { get }
    func versionDirectory(_ id: UUID) -> URL
}

extension SessionLocationPaths {
    package var repositoryImportID: UUID? { nil }
    package func runDirectory(for id: UUID) -> GameRunDirectory { instanceRunDirectories?[id] ?? .isolated }
    package func repositoryImportWorkspace(_ id: UUID) -> URL { SessionOperation.repositoryImport.url(paths: self, instanceID: id) }
    package func isMinecraftDirectory(_ id: UUID) -> Bool { directories.first(where: { $0.id == id })?.isMinecraft == true }
    package func directoryID(for instanceID: UUID) -> UUID { instanceDirectories[instanceID] ?? newInstanceDirectoryID }
    package func directoryRoot(_ id: UUID) -> URL {
        if id == GameDirectory.defaultID { return root }
        // Invalid references must never silently become the default directory.
        return directories.first(where: { $0.id == id })?.url ?? root.appendingPathComponent("unavailable-directories/\(id.uuidString)")
    }
    // Concrete paths expose these through their own access levels. Only Core
    // overrides instance/version directories while an import is unpublished.
    package func resolvedInstanceDirectory(_ id: UUID) -> URL {
        directoryRoot(directoryID(for: id))
            .appendingPathComponent(isMinecraftDirectory(directoryID(for: id)) ? ".ruri/instances" : "instances")
            .appendingPathComponent(id.uuidString)
    }
    package func resolvedVersionDirectory(_ id: UUID) -> URL {
        directoryRoot(directoryID(for: id)).appendingPathComponent("versions")
            .appendingPathComponent(instanceRepositoryVersions?[id] ?? "unavailable-\(id.uuidString)")
    }
    package func resolvedGameDirectory(_ id: UUID) -> URL {
        if runDirectory(for: id) == .custom {
            return instanceCustomDirectories?[id]?.url ?? root.appendingPathComponent("unavailable-run-directories/\(id.uuidString)")
        }
        if isMinecraftDirectory(directoryID(for: id)) {
            return runDirectory(for: id) == .isolated ? versionDirectory(id) : directoryRoot(directoryID(for: id))
        }
        return (runDirectory(for: id) == .isolated ? instance(id) : directoryRoot(directoryID(for: id))).appendingPathComponent("minecraft")
    }
    package func resolvedGameDataState(_ id: UUID) -> URL {
        runDirectory(for: id) == .isolated ? instance(id) : game(id).appendingPathComponent(".ruri")
    }
    package func validateDirectoryConfiguration() throws {
        let ids = directories.map(\.id)
        guard root.isFileURL, Set(ids).count == ids.count, !ids.contains(GameDirectory.defaultID), directories.count <= 100,
              Set(instanceDirectories.values).union([newInstanceDirectoryID]).subtracting([GameDirectory.defaultID]).isSubset(of: Set(ids)) else { throw RuriError.message(Messages.CoreGameDirectory.invalidRegistration) }
        for directory in directories {
            _ = try GameDirectory.validName(directory.name)
            guard directory.url.isFileURL, directory.url.path.hasPrefix("/"), (directory.bookmark?.count ?? 0) <= 1_048_576 else { throw RuriError.message(Messages.CoreGameDirectory.invalidLocation) }
            try checkDirectoryOverlap(directory)
        }
        for (id, version) in instanceRepositoryVersions ?? [:] {
            try SessionFileSystem.checkVersionIdentifier(version)
            guard isMinecraftDirectory(directoryID(for: id)) else { throw RuriError.message(Messages.CoreGameDirectory.missingMinecraftFolder) }
        }
        for (id, directory) in instanceDirectories where isMinecraftDirectory(directory) {
            guard instanceRepositoryVersions?[id] != nil else { throw RuriError.message(Messages.CoreGameDirectory.missingVersionDirectory) }
        }
        for (id, mode) in instanceRunDirectories ?? [:] where mode == .custom {
            guard let custom = instanceCustomDirectories?[id] else { throw RuriError.message(Messages.CoreGameDirectory.missingCustomRunDirectory) }
            try checkCustomRunDirectory(custom)
        }
        for (id, custom) in instanceCustomDirectories ?? [:] {
            guard instanceRunDirectories?[id] == .custom else { throw RuriError.message(Messages.CoreGameDirectory.customDirectoryMismatch) }
            for other in (instanceCustomDirectories ?? [:]).values where other.url.standardizedFileURL == custom.url.standardizedFileURL {
                guard other.id == custom.id else { throw RuriError.message(Messages.CoreGameDirectory.duplicateCustomDirectory) }
            }
        }
    }
    package func checkDirectoryOverlap(_ directory: GameDirectory) throws {
        let target = directory.url.standardizedFileURL.resolvingSymlinksInPath().path
        for other in [root] + directories.filter({ $0.id != directory.id }).map(\.url) + (instanceCustomDirectories ?? [:]).values.map(\.url).filter({ !directory.isMinecraft || !$0.path.hasPrefix(target + "/") }) {
            let existing = other.standardizedFileURL.resolvingSymlinksInPath().path
            guard target != existing, !target.hasPrefix(existing + "/"), !existing.hasPrefix(target == "/" ? "/" : target + "/") else {
                throw RuriError.message(Messages.CoreGameDirectory.overlappingDirectory)
            }
        }
    }
    package func validateInstanceLocation(_ instanceID: UUID) throws {
        let id = directoryID(for: instanceID)
        if id != GameDirectory.defaultID {
            guard let directory = directories.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CoreGameDirectory.missingParentDirectory) }
            try directory.validateAvailability()
        }
        // The selected directory is trusted; its internal managed tree may not
        // escape through a symlink, including one with a not-yet-created leaf.
        let root = directoryRoot(id)
        if isMinecraftDirectory(id) {
            guard let version = instanceRepositoryVersions?[instanceID] else { throw RuriError.message(Messages.CoreGameDirectory.missingVersionFolder) }
            try SessionFileSystem.checkVersionIdentifier(version)
            _ = try SessionFileSystem.safePath("versions/\(version)/\(version).json", within: root)
            _ = try SessionFileSystem.safePath(".ruri/instances/\(instanceID.uuidString)", within: root)
            if repositoryImportID == instanceID {
                let workspace = try SessionOperation.repositoryImport.checkedURL(paths: self, instanceID: instanceID)
                _ = try SessionFileSystem.safePath("version/\(version).json", within: workspace)
                _ = try SessionFileSystem.safePath("metadata", within: workspace)
            }
        } else {
            _ = try SessionFileSystem.safePath("instances/\(instanceID.uuidString)/minecraft", within: root)
            if runDirectory(for: instanceID) == .shared { _ = try SessionFileSystem.safePath("minecraft/.ruri", within: root) }
        }
        if runDirectory(for: instanceID) == .custom {
            guard let custom = instanceCustomDirectories?[instanceID] else { throw RuriError.message(Messages.CoreGameDirectory.requireCustomDirectory) }
            try custom.validateAvailability()
            _ = try SessionFileSystem.safePath(".ruri", within: custom.url)
        }
    }
}


extension SessionLocationPaths {
    package func checkCustomRunDirectory(_ selected: CustomRunDirectory, relocatingID: UUID? = nil, readingIdentity: Bool = false) throws {
        try selected.validateConfiguration()
        let target = selected.url.standardizedFileURL.resolvingSymlinksInPath().path
        func overlaps(_ first: String, _ second: String) -> Bool {
            first == second || first.hasPrefix(second == "/" ? "/" : second + "/") || second.hasPrefix(first == "/" ? "/" : first + "/")
        }
        for managed in [root] + directories.map({ $0.isMinecraft ? $0.url.appendingPathComponent(".ruri") : $0.url }) {
            guard !overlaps(target, managed.standardizedFileURL.resolvingSymlinksInPath().path) else { throw RuriError.message(Messages.CoreCustomRunDirectory.overlappingDirectory) }
        }
        for other in (instanceCustomDirectories ?? [:]).values where other.id != relocatingID {
            let existing = other.url.standardizedFileURL.resolvingSymlinksInPath().path
            if existing == target {
                guard readingIdentity || selected.id == other.id else { throw RuriError.message(Messages.CoreCustomRunDirectory.identityChanged) }
                continue
            }
            guard selected.id != other.id else { throw RuriError.message(Messages.CoreCustomRunDirectory.duplicateDirectory) }
            guard !overlaps(target, existing) else { throw RuriError.message(Messages.CoreCustomRunDirectory.nestedDirectories) }
        }
    }
}
