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
