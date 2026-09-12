import RuriLocalization
import Foundation

extension GameInstance {
    /// Publish only fields produced by installation. User preferences may have
    /// changed while downloads were running, so the original copy is not a new
    /// authoritative instance record.
    public func applyingInstallation(_ result: GameInstance, requested: GameInstance) throws -> GameInstance {
        guard id == requested.id, result.id == id, repositoryVersionID == requested.repositoryVersionID, result.repositoryVersionID == repositoryVersionID,
              gameVersion == requested.gameVersion, result.gameVersion == gameVersion,
              loader == requested.loader, result.loader == loader,
              loaderVersion == requested.loaderVersion || loaderVersion == result.loaderVersion,
              (directoryID ?? GameDirectory.defaultID) == (requested.directoryID ?? GameDirectory.defaultID),
              (result.directoryID ?? GameDirectory.defaultID) == (directoryID ?? GameDirectory.defaultID),
              (runDirectory ?? .isolated) == (requested.runDirectory ?? .isolated),
              (result.runDirectory ?? .isolated) == (runDirectory ?? .isolated) else {
            throw RuriError.message(Messages.CoreInstallationState.applyingInstallationText1)
        }
        if runDirectory == .custom {
            guard let current = customRunDirectory, let original = requested.customRunDirectory, let installed = result.customRunDirectory,
                  current.isSameLocation(as: original), current.isSameLocation(as: installed) else { throw RuriError.message(Messages.CoreInstallationState.installedText1) }
        }
        var current = self
        current.installed = result.installed; current.loaderVersion = result.loaderVersion; current.directoryID = result.directoryID
        return current
    }
}
