import Foundation

enum GameSessionRetention {
    static func prune(paths: LauncherPaths, instanceID: UUID, keeping currentID: UUID) throws {
        let lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID, ignoringSession: currentID)
        defer { withExtendedLifetime(lease) {} }
        try SessionArtifactRetention.prune(paths: paths, instanceID: instanceID, keeping: currentID)
    }
}
