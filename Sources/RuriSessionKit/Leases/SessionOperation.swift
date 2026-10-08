import Foundation
import RuriLocalization

/// Durable barriers shared by transaction writers and session handoff. Global
/// registration checks and transaction recovery permissions remain in Core.
package enum SessionOperation: String, CaseIterable {
    case instanceMove = "instance-move-transactions"
    case instanceCopy = "instance-copy-transactions"
    case copyPublication = ".ruri-instance-copy.json"
    case runDirectoryChange = "run-directory-change"
    case sharedDirectoryChange = "directory-change.json"
    case modpackUpdate = "modpack-update-transaction/journal.json"
    case repositoryImport = ".ruri/imports"

    package var filename: String { (rawValue as NSString).lastPathComponent }

    private func location(paths: any SessionLocationPaths, instanceID: UUID) -> (root: URL, relative: String) {
        switch self {
        case .instanceMove, .instanceCopy:
            (paths.root, "\(rawValue)/\(instanceID.uuidString)")
        case .copyPublication, .runDirectoryChange, .modpackUpdate:
            (paths.instance(instanceID), rawValue)
        case .sharedDirectoryChange:
            (paths.resolvedGameDataState(instanceID), rawValue)
        case .repositoryImport:
            (paths.directoryRoot(paths.directoryID(for: instanceID)), "\(rawValue)/\(instanceID.uuidString)")
        }
    }
    package func url(paths: any SessionLocationPaths, instanceID: UUID) -> URL {
        let location = location(paths: paths, instanceID: instanceID)
        return location.root.appendingPathComponent(location.relative)
    }
    package func checkedURL(paths: any SessionLocationPaths, instanceID: UUID) throws -> URL {
        let location = location(paths: paths, instanceID: instanceID)
        return try SessionFileSystem.safePath(location.relative, within: location.root)
    }
    package func hasPending(paths: any SessionLocationPaths, instanceID: UUID) -> Bool {
        if self == .sharedDirectoryChange && paths.runDirectory(for: instanceID) == .isolated { return false }
        if self == .repositoryImport && !paths.isMinecraftDirectory(paths.directoryID(for: instanceID)) { return false }
        guard let marker = try? checkedURL(paths: paths, instanceID: instanceID) else { return true }
        return FileManager.default.fileExists(atPath: marker.path)
    }
    package static func requireNoPending(paths: any SessionLocationPaths, instanceID: UUID) throws {
        for operation in allCases where operation.hasPending(paths: paths, instanceID: instanceID) {
            switch operation {
            case .sharedDirectoryChange: throw RuriError.message(Messages.CoreRunDirectoryCopyJournal.unfinishedCopy)
            case .repositoryImport: throw RuriError.message(Messages.CoreInstanceLocationLease.requireCurrentDirectory)
            default: throw RuriError.message(Messages.CoreGameRunLease.activeRunSession)
            }
        }
    }
}
