import Foundation

/// Runs between games under the instance lease, never on a periodic timer.
/// Unfinished and unrecognized directories are never removed. Permanent
/// metadata is archived before diagnostic files are eligible for deletion.
enum GameSessionRetention {
    static func prune(paths: LauncherPaths, instanceID: UUID, keeping currentID: UUID) throws {
        let lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID, ignoringSession: currentID)
        defer { withExtendedLifetime(lease) {} }
        let root = try LauncherPaths.safePath("diagnostics", within: paths.instance(instanceID))
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let records = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).compactMap { url -> GameSession? in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            return try? GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: id)
        }
        var normal = 0, diagnostic = 0, bytes: Int64 = 0
        // The current run is always kept, even if debug output uses its budget.
        let sorted = records.sorted { ($0.id == currentID ? 0 : 1, -$0.createdAt.timeIntervalSince1970) < ($1.id == currentID ? 0 : 1, -$1.createdAt.timeIntervalSince1970) }
        for record in sorted where record.state.isFinished {
            if record.id != currentID {
                let identities = [record.monitorIdentity, record.gameIdentity, record.commandIdentity].compactMap { $0 }
                guard identities.allSatisfy({ $0.liveness == .exited }) else { continue }
            }
            let root = try LauncherPaths.safePath("diagnostics", within: paths.instance(instanceID))
            let directory = root.appendingPathComponent(record.id.uuidString)
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let isDiagnostic = record.needsAttention || record.debugLogging == true || record.commandResults?.contains(where: { !$0.succeeded && !$0.cancelled }) == true
            if isDiagnostic { diagnostic += 1 } else { normal += 1 }
            let size = try directorySize(directory)
            let budget: Int64 = 96 * 1_048_576
            if record.id != currentID && ((isDiagnostic ? diagnostic > 3 : normal > 10) || size > budget - bytes) {
                try GameHistoryStore.archive(record, paths: paths)
                try FileManager.default.removeItem(at: directory)
                try GameHistoryStore.markArtifactsExpired(sessionID: record.id, paths: paths)
            } else { bytes += size }
        }
    }

    private static func directorySize(_ directory: URL) throws -> Int64 {
        var size: Int64 = 0
        guard let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return 0 }
        for case let file as URL in entries {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if values.isSymbolicLink == true { entries.skipDescendants(); continue }
            if values.isRegularFile == true { size += Int64(values.fileSize ?? 0) }
        }
        return size
    }
}
