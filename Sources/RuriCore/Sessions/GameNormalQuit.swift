import RuriLocalization
import Foundation
import AppKit

public struct GameNormalQuitAttempt: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let requestedAt: Date
    public let processedAt: Date
    public let accepted: Bool
    public var explanation: String { explanationMessage.localized }
    public var explanationMessage: LocalizedMessage {
        accepted ? Messages.CoreGameNormalQuit.normalExitRequestPending
                 : Messages.CoreGameNormalQuit.normalExitRequestFailed
    }
}

public enum NativeGameQuit {
    /// An accepted request is not an exit acknowledgement. Cocoa/GLFW may
    /// decline or defer it; only the process owner records the eventual exit.
    @MainActor public static func request(_ identity: ProcessIdentity) -> Bool {
        guard identity.isAlive,
              let application = NSRunningApplication(processIdentifier: identity.pid), !application.isTerminated, application.activationPolicy != .prohibited,
              identity.isAlive else { return false }
        return application.terminate()
    }
}

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
