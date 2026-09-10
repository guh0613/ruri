import Foundation
import Darwin

/// A shared run directory has one writer, even when instances or launcher
/// clients differ. The persistent reservation covers monitor handoff and loss.
final class SharedGameDirectoryLease: @unchecked Sendable {
    private let descriptor: Int32
    private let root: URL
    private init(_ descriptor: Int32, root: URL) { self.descriptor = descriptor; self.root = root }
    deinit { close(descriptor) }
    private struct Reservation: Codable {
        let version: Int
        let paths: LauncherPaths
        let instanceID: UUID
        let sessionID: UUID
    }
    static func acquire(paths: LauncherPaths, instanceID: UUID, ignoringSession: UUID?, directoryChangeID: UUID? = nil) throws -> SharedGameDirectoryLease {
        try paths.validateInstanceLocation(instanceID)
        let root = paths.game(instanceID)
        let metadata = try LauncherPaths.safePath(".ruri", within: root)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let url = try LauncherPaths.safePath("run.lock", within: metadata)
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message("无法锁定共享运行目录。") }
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            close(fd); throw RuriError.message("此运行目录正被另一个实例使用，请先结束游戏或等待文件操作完成。")
        }
        let result = SharedGameDirectoryLease(fd, root: root)
        try RunDirectoryCopyGuard.requireSharedAvailable(paths: paths, instanceID: instanceID, allowing: directoryChangeID)
        try result.checkReservation(instanceID: instanceID, ignoringSession: ignoringSession, paths: paths)
        return result
    }
    static func isHeld(paths: LauncherPaths, instanceID: UUID) -> Bool {
        guard let url = try? LauncherPaths.safePath(".ruri/run.lock", within: paths.game(instanceID)) else { return true }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let fd = open(url.path, O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return true }; defer { close(fd) }
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        return fstat(fd, &info) != 0 || info.st_mode & S_IFMT != S_IFREG || fcntl(fd, F_OFD_SETLK, &lock) != 0
    }
    func reserve(paths: LauncherPaths, session: GameSession) throws {
        let file = try LauncherPaths.safePath(".ruri/active-session.json", within: root)
        let reservation = Reservation(version: 2, paths: paths.monitorSnapshot(for: session.instanceID), instanceID: session.instanceID, sessionID: session.id)
        try JSONEncoder().encode(reservation).write(to: file, options: .atomic)
    }
    func clearReservation(session: GameSession) throws {
        guard session.state.isFinished else { return }
        let file = try LauncherPaths.safePath(".ruri/active-session.json", within: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? .max) <= 131_072 else { throw RuriError.message("共享目录运行记录无效。") }
        let reservation = try JSONDecoder().decode(Reservation.self, from: Data(contentsOf: file))
        guard reservation.instanceID == session.instanceID, reservation.sessionID == session.id else { return }
        try FileManager.default.removeItem(at: file)
    }
    func clearFinishedReservation(paths: LauncherPaths, instanceID: UUID) throws {
        let file = try LauncherPaths.safePath(".ruri/active-session.json", within: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let reservation: Reservation = try RunDirectoryCopyGuard.decode(file, limit: 131_072)
        guard reservation.instanceID == instanceID else { return }
        let session = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: reservation.sessionID)
        guard session.state.isFinished,
              session.monitorIdentity.map({ $0.liveness == .exited }) ?? true,
              session.gameIdentity.map({ $0.liveness == .exited }) ?? true else { throw RuriError.message("共享目录的上次运行尚未确认结束，无法移动其历史。") }
        try clearReservation(session: session)
    }
    private func checkReservation(instanceID: UUID, ignoringSession: UUID?, paths: LauncherPaths) throws {
        let file = try LauncherPaths.safePath(".ruri/active-session.json", within: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 131_072 else { throw RuriError.message("共享目录的运行记录无效，请检查运行历史。") }
        let reservation = try JSONDecoder().decode(Reservation.self, from: Data(contentsOf: file))
        guard (1...2).contains(reservation.version), reservation.paths.instanceDirectories.count == 1,
              reservation.paths.instanceDirectories[reservation.instanceID] != nil,
              reservation.paths.runDirectory(for: reservation.instanceID) != .isolated else {
            throw RuriError.message("共享运行目录与上次运行记录不一致，请检查原实例。")
        }
        if reservation.paths.runDirectory(for: reservation.instanceID) == .custom, reservation.version < 2 { throw RuriError.message("自定义运行目录的占用记录版本无效。") }
        try reservation.paths.validateDirectoryConfiguration()
        var checked = reservation.paths
        if let collection = paths.directories.first(where: { $0.id == reservation.paths.directoryID(for: reservation.instanceID) }) {
            let directories = checked.directories.map { $0.id == collection.id ? collection : $0 }
            checked = LauncherPaths(root: checked.root, directories: directories, instanceDirectories: checked.instanceDirectories,
                                    newInstanceDirectoryID: checked.newInstanceDirectoryID, instanceRunDirectories: checked.instanceRunDirectories, instanceCustomDirectories: checked.instanceCustomDirectories, instanceRepositoryVersions: checked.instanceRepositoryVersions)
        }
        if let custom = paths.instanceCustomDirectories?[instanceID], let original = checked.instanceCustomDirectories?[reservation.instanceID], original.id == custom.id {
            // The marker identifies a moved custom root, while its history
            // remains in the original collection. Liveness is still checked
            // below; matching a marker never clears an active reservation.
            var locations = checked.instanceCustomDirectories ?? [:]; locations[reservation.instanceID] = custom
            checked = LauncherPaths(root: checked.root, directories: checked.directories,
                                    instanceDirectories: checked.instanceDirectories, newInstanceDirectoryID: checked.newInstanceDirectoryID,
                                    instanceRunDirectories: checked.instanceRunDirectories, instanceCustomDirectories: locations, instanceRepositoryVersions: checked.instanceRepositoryVersions)
        } else {
            guard checked.game(reservation.instanceID).standardizedFileURL.resolvingSymlinksInPath().path == root.standardizedFileURL.resolvingSymlinksInPath().path else { throw RuriError.message("共享运行目录与上次运行记录不一致，请检查原实例。") }
        }
        try checked.validateDirectoryConfiguration()
        try checked.validateInstanceLocation(reservation.instanceID)
        if reservation.instanceID == instanceID && reservation.sessionID == ignoringSession { return }
        let record = try GameSessionStore.load(paths: checked, instanceID: reservation.instanceID, sessionID: reservation.sessionID)
        guard record.state.isFinished || (record.monitorIdentity != nil && GameMonitorClient.activity(record) == .inactive) else {
            throw RuriError.message("“\(record.instanceName)”仍在使用此共享目录，或上次运行状态尚未确认。请先返回该实例检查运行记录。")
        }
    }
}
