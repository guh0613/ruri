import Foundation

extension GameInstance {
    /// Publish only fields produced by installation. User preferences may have
    /// changed while downloads were running, so the original copy is not a new
    /// authoritative instance record.
    public func applyingInstallation(_ result: GameInstance, requested: GameInstance) throws -> GameInstance {
        guard id == requested.id, result.id == id,
              gameVersion == requested.gameVersion, result.gameVersion == gameVersion,
              loader == requested.loader, result.loader == loader,
              loaderVersion == requested.loaderVersion || loaderVersion == result.loaderVersion,
              (directoryID ?? GameDirectory.defaultID) == (requested.directoryID ?? GameDirectory.defaultID),
              (result.directoryID ?? GameDirectory.defaultID) == (directoryID ?? GameDirectory.defaultID),
              (runDirectory ?? .isolated) == (requested.runDirectory ?? .isolated),
              (result.runDirectory ?? .isolated) == (runDirectory ?? .isolated) else {
            throw RuriError.message("实例的版本或目录在安装期间改变，未覆盖最新设置。请重新检查实例。")
        }
        var current = self
        current.installed = result.installed; current.loaderVersion = result.loaderVersion; current.directoryID = result.directoryID
        return current
    }
}
