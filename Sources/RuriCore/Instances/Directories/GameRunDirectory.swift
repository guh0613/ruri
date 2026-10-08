import Foundation
import RuriLocalization

public enum GameIsolationPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case always, modded, never
    public var id: String { rawValue }
    public var title: String { switch self { case .always: Messages.CoreGameRunDirectory.allNewInstancesIsolated.localized; case .modded: Messages.CoreGameRunDirectory.loaderInstancesIsolated.localized; case .never: Messages.CoreGameRunDirectory.newInstancesShared.localized } }
    public func directory(loader: LoaderKind) -> GameRunDirectory {
        switch self { case .always: .isolated; case .modded: loader == .vanilla ? .shared : .isolated; case .never: .shared }
    }
}

extension LauncherPaths {
    public func validateBinding(_ instance: GameInstance) throws {
        guard instanceRepositoryVersions?[instance.id] == instance.repositoryVersionID, runDirectory(for: instance.id) == (instance.runDirectory ?? .isolated),
              instance.directoryID == nil || instance.directoryID == directoryID(for: instance.id) else {
            throw RuriError.message(Messages.CoreGameRunDirectory.bindingMismatch)
        }
        if runDirectory(for: instance.id) == .custom {
            guard let expected = instance.customRunDirectory, let actual = instanceCustomDirectories?[instance.id], expected.isSameLocation(as: actual) else { throw RuriError.message(Messages.CoreGameRunDirectory.customPathMismatch) }
        }
        try validateInstanceLocation(instance.id)
    }
    public func runDirectory(for instanceID: UUID) -> GameRunDirectory { instanceRunDirectories?[instanceID] ?? .isolated }
    /// Metadata that describes the game files must follow the run directory.
    /// Old isolated instances retain their existing metadata and backup paths.
    public func gameDataState(_ instanceID: UUID) -> URL {
        resolvedGameDataState(instanceID)
    }
    public func including(_ instance: GameInstance) -> LauncherPaths {
        var versions = instanceRepositoryVersions ?? [:]
        versions[instance.id] = instance.repositoryVersionID
        var directoriesByInstance = instanceDirectories, modes = instanceRunDirectories ?? [:], custom = instanceCustomDirectories ?? [:]
        directoriesByInstance[instance.id] = instance.directoryID ?? directoryID(for: instance.id)
        modes[instance.id] = instance.runDirectory ?? .isolated
        custom[instance.id] = instance.runDirectory == .custom ? instance.customRunDirectory : nil
        var result = LauncherPaths(root: root, directories: directories, instanceDirectories: directoriesByInstance, newInstanceDirectoryID: newInstanceDirectoryID, instanceRunDirectories: modes, instanceCustomDirectories: custom, instanceRepositoryVersions: versions)
        result.repositoryImportID = repositoryImportID
        return result
    }
}
