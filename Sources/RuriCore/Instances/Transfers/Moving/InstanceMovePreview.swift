import RuriLocalization
import Foundation
import Darwin

public struct InstanceMovePreview: Identifiable, Sendable {
    public let id: UUID
    public let source: GameInstance
    public let moved: GameInstance
    public let sourceDirectory: URL
    public let destination: URL
    public let sourceGame: URL
    public let destinationGame: URL
    /// Shared and custom game files remain at their original location.
    public var retainedGameDirectory: URL? { source.runDirectory == .shared || source.runDirectory == .custom ? sourceGame : nil }
    public var fileCount: Int { snapshot.destination.entries.filter { !$0.directory }.count + (repository?.installation.fileCount ?? 0) }
    public var bytes: Int64 { snapshot.destination.entries.reduce(0) { $0 + $1.size } + (repository?.installation.bytes ?? 0) }
    public var preservedPreviousData: URL? {
        snapshot.hasPreviousData ? destination.appendingPathComponent(InstanceMoveSnapshot.previousDataPath(id)) : nil
    }
    let sourceCollection: GameDirectory?
    let targetCollection: GameDirectory?
    let sourceIdentity: RunDirectoryCopyJournal.Identity
    let snapshot: InstanceMoveSnapshot
    var repository: RepositoryMoveSnapshot? = nil
}

public actor InstanceMover {
    let paths: LauncherPaths
    public init(paths: LauncherPaths) { self.paths = paths }

    public func preview(instanceID: UUID, directoryID: UUID) async throws -> InstanceMovePreview {
        try Task.checkCancellation()
        let state = try StateStore.load(paths), current = paths.configured(with: state)
        guard let source = state.instances.first(where: { $0.id == instanceID }) else { throw RuriError.message(Messages.CoreInstanceMovePreview.sourceInstanceMissing) }
        if source.repositoryVersionID != nil || current.isMinecraftDirectory(directoryID) {
            return try await repositoryPreview(source: source, directoryID: directoryID, paths: current)
        }
        guard current.directoryID(for: instanceID) != directoryID else { throw RuriError.message(Messages.CoreInstanceMovePreview.sourceAlreadyInTarget) }
        guard directoryID == GameDirectory.defaultID || current.directories.contains(where: { $0.id == directoryID }) else { throw RuriError.message(Messages.CoreInstanceMovePreview.targetInstanceMissing) }
        let id = UUID()
        var moved = source; moved.directoryID = directoryID; moved.lastInstanceMoveID = id
        if source.runDirectory == .shared {
            moved.runDirectory = .isolated; moved.customRunDirectory = nil; moved.lastRunDirectoryChangeID = nil
        }
        let target = current.including(moved)
        try target.validateInstanceLocation(instanceID)
        try Self.requireAbsent(target.instance(instanceID))
        let access = try await InstanceMoveAccess.acquire(instance: source, paths: current)
        defer { withExtendedLifetime(access) {} }
        let identity = try RunDirectoryCopyJournal.Identity.read(current.instance(instanceID))
        let snapshot = try InstanceMoveSnapshot.capture(instance: source, paths: current, transactionID: id)
        guard identity.matches(current.instance(instanceID)) else { throw RuriError.message(Messages.CoreInstanceMovePreview.sourceFolderReplacedDuringPreview) }
        // A download or another settings window can finish while files are hashed.
        guard try StateStore.load(paths).instances.first(where: { $0.id == instanceID }) == source else { throw RuriError.message(Messages.CoreInstanceMovePreview.settingsChangedDuringPreview) }
        func collection(_ id: UUID) -> GameDirectory? {
            var value = current.directories.first { $0.id == id }; value?.bookmark = nil; return value
        }
        return .init(id: id, source: source, moved: moved, sourceDirectory: current.instance(instanceID),
                     destination: target.instance(instanceID), sourceGame: current.game(instanceID), destinationGame: target.game(instanceID),
                     sourceCollection: collection(current.directoryID(for: instanceID)), targetCollection: collection(directoryID),
                     sourceIdentity: identity, snapshot: snapshot)
    }

    /// Call under the source's operation locks immediately before activating a
    /// move. A preview is a file snapshot, not permission to move later changes.
    func validate(_ preview: InstanceMovePreview, state: PersistentState) throws {
        guard state.instances.first(where: { $0.id == preview.source.id }) == preview.source else { throw RuriError.message(Messages.CoreInstanceMovePreview.settingsChangedAfterPreview) }
        let current = paths.configured(with: state), target = current.including(preview.moved)
        try current.validateInstanceLocation(preview.source.id); try target.validateInstanceLocation(preview.moved.id)
        guard current.instance(preview.source.id).standardizedFileURL == preview.sourceDirectory.standardizedFileURL,
              target.instance(preview.moved.id).standardizedFileURL == preview.destination.standardizedFileURL,
              preview.sourceIdentity.matches(preview.sourceDirectory) else { throw RuriError.message(Messages.CoreInstanceMovePreview.locationChangedAfterPreview) }
        try Self.requireAbsent(preview.destination)
        try preview.snapshot.requireUnchanged(instance: preview.source, paths: current, transactionID: preview.id)
    }

    static func requireAbsent(_ url: URL) throws {
        // fileExists does not see dangling symlinks; those must not be replaced.
        var info = stat()
        if lstat(url.path, &info) == 0 {
            throw RuriError.message(Messages.CoreInstanceMovePreview.targetAlreadyContainsInstance)
        }
        guard errno == ENOENT else { throw RuriError.message(Messages.CoreInstanceMovePreview.targetAvailabilityUnknown) }
    }
}
