import Foundation

/// Runs between games under the instance lease, never on a periodic timer.
/// Active, interrupted and unrecognized directories are never removed.
enum GameSessionRetention {
    static func prune(paths: LauncherPaths, instanceID: UUID, keeping currentID: UUID) throws {
        let lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID, ignoringSession: currentID)
        defer { withExtendedLifetime(lease) {} }
        let records = try GameSessionStore.list(paths: paths, instanceID: instanceID)
        var normal = 0, diagnostic = 0, bytes: Int64 = 0
        var removed = Set<UUID>()
        defer { try? GamePlaytimeStore.compact(paths: paths, instanceID: instanceID, removing: removed) }
        // The current run is always kept, even if debug output uses its budget.
        let sorted = records.sorted { ($0.id == currentID ? 0 : 1, -$0.createdAt.timeIntervalSince1970) < ($1.id == currentID ? 0 : 1, -$1.createdAt.timeIntervalSince1970) }
        for record in sorted where record.state.isFinished && record.state != .interrupted {
            if record.id != currentID {
                let identities = [record.monitorIdentity, record.gameIdentity, record.commandIdentity].compactMap { $0 }
                guard identities.allSatisfy({ $0.liveness == .exited }) else { continue }
            }
            let root = try LauncherPaths.safePath("sessions", within: paths.instance(instanceID))
            let directory = root.appendingPathComponent(record.id.uuidString)
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let isDiagnostic = record.state == .failed || record.debugLogging == true || record.commandResults?.contains(where: { !$0.succeeded && !$0.cancelled }) == true
            if isDiagnostic { diagnostic += 1 } else { normal += 1 }
            let size = try directorySize(directory)
            let budget: Int64 = 96 * 1_048_576
            if record.id != currentID && ((isDiagnostic ? diagnostic > 3 : normal > 10) || size > budget - bytes) {
                try FileManager.default.removeItem(at: directory)
                removed.insert(record.id)
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
