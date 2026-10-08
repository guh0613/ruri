import Foundation
@testable import RuriCore
@testable import RuriMonitorRuntime

/// Domain tests can drive runtime recording without launching a game. The
/// real preparation object retains its lease until runtime recording closes.
extension MonitorSessionRecorder {
    convenience init(paths: LauncherPaths, instance: GameInstance, accountMode: String) throws {
        let preparation = try GameSessionRecorder(paths: paths, instance: instance, accountMode: accountMode)
        self.init(writer: preparation.writer) { _ in try preparation.close() }
    }
    convenience init(resuming sessionID: UUID, instanceID: UUID, paths: LauncherPaths, monitor: ProcessIdentity) throws {
        try self.init(resuming: sessionID, instanceID: instanceID,
                      paths: SessionLocationSnapshot(paths: paths, instanceID: instanceID), monitor: monitor)
    }
}

extension LauncherPaths {
    /// The pre-extraction v1 encoder, retained only to verify old payloads.
    func legacyMonitorSnapshot(for instanceID: UUID) -> LauncherPaths {
        let id = directoryID(for: instanceID)
        let selected = directories.filter { $0.id == id }.map { item in var item = item; item.bookmark = nil; return item }
        var custom = instanceCustomDirectories?[instanceID]; custom?.bookmark = nil
        return LauncherPaths(root: root, directories: selected, instanceDirectories: [instanceID: id], instanceRunDirectories: [instanceID: runDirectory(for: instanceID)], instanceCustomDirectories: custom.map { [instanceID: $0] }, instanceRepositoryVersions: instanceRepositoryVersions?[instanceID].map { [instanceID: $0] })
    }
}
