import Foundation

public enum GameMonitorActivity: Equatable, Sendable { case inactive, monitoring, orphaned, uncertain }

extension GameSession {
    package var monitorActivity: GameMonitorActivity {
        let record = self
        if record.monitorIdentity?.isAlive == true { return .monitoring }
        if record.state.isFinished || record.monitorIdentity == nil { return .inactive }
        if record.monitorIdentity?.liveness == .unverifiable { return .uncertain }
        if record.gameIdentity?.isAlive == true || record.commandIdentity?.isAlive == true { return .orphaned }
        // A monitor may have died between spawning Java and saving its identity.
        if record.gameIdentity == nil || record.gameIdentity?.liveness == .unverifiable { return .uncertain }
        return .inactive
    }
}
