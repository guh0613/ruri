import RuriLocalization
import Foundation
import AppKit

extension GameMonitorClient {
    @discardableResult public static func requestNormalQuit(paths: LauncherPaths, record: GameSession) throws -> UUID {
        let current = try GameSessionStore.load(paths: paths, instanceID: record.instanceID, sessionID: record.id)
        guard !current.state.isFinished, current.monitorIdentity == record.monitorIdentity,
              current.gameIdentity == record.gameIdentity, current.monitorIdentity?.isAlive == true,
              current.gameIdentity?.isAlive == true else { throw RuriError.message(Messages.CoreGameNormalQuit.quitStateChanged) }
        guard current.nativeQuitSupported == true else { throw RuriError.message(Messages.CoreGameNormalQuit.appExitRequestDisabled) }
        guard current.controlEndpoint != nil else { throw RuriError.message(Messages.CoreGameMonitor.monitorDisconnected) }
        let reply = try MonitorSocket.request(current, command: .quit)
        try? recordEvent(.normalQuitRequested, paths: paths, session: current)
        return reply.requestID
    }
}
