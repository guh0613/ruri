import Foundation
import Darwin

/// A user-selected game root, separate from Ruri's managed instance metadata.
/// Its marker travels with Finder moves and detects replacement at an old path.
public struct CustomRunDirectory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var url: URL
    public var bookmark: Data?
    public let createdAt: Date
    private struct Marker: Codable { let version: Int; let id: UUID }
    private static let markerPath = ".ruri/run-directory.json"

    /// Registers coordination metadata only. Existing game files are preserved.
    public static func register(at selected: URL, paths: LauncherPaths) throws -> Self {
        let url = selected.standardizedFileURL.resolvingSymlinksInPath()
        var candidate = Self(id: UUID(), url: url, bookmark: nil, createdAt: Date())
        try paths.checkCustomRunDirectory(candidate, readingIdentity: true)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message("请选择已存在的游戏文件夹。") }
        let marker = try LauncherPaths.safePath(markerPath, within: url)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lock = GameDataOperationLock(); try lock.acquire(directory: marker.deletingLastPathComponent(), name: ".location-registration.lock")
        defer { withExtendedLifetime(lock) {} }
        if FileManager.default.fileExists(atPath: marker.path) {
            let previous = try readMarker(marker)
            candidate = Self(id: previous.id, url: url, bookmark: nil, createdAt: Date())
        } else {
            try JSONEncoder().encode(Marker(version: 1, id: candidate.id)).write(to: marker, options: .withoutOverwriting)
        }
        try paths.checkCustomRunDirectory(candidate)
        candidate.bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try candidate.validateAvailability()
        return candidate
    }

    public func isSameLocation(as other: Self) -> Bool {
        id == other.id && url.standardizedFileURL.path == other.url.standardizedFileURL.path
    }
    func validateConfiguration() throws {
        guard id != GameDirectory.defaultID, url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"),
              url.path.count <= 32768, (bookmark?.count ?? 0) <= 1_048_576 else { throw RuriError.message("自定义运行目录登记信息无效。") }
    }
    public func validateAvailability() throws {
        do {
            try validateConfiguration()
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw RuriError.message("路径已失联或不再是原文件夹。") }
            let record = try Self.readMarker(LauncherPaths.safePath(Self.markerPath, within: url))
            guard record.id == id else { throw RuriError.message("目录身份与选取时不一致。") }
        } catch {
            throw RuriError.message("无法访问自定义运行目录：\(url.path)\n请连接原磁盘、检查权限或重新定位原文件夹。\n\(error.localizedDescription)")
        }
    }
    public func resolvingBookmark() -> Self {
        guard let bookmark else { return self }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return self }
        var result = self; result.url = url.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? result.validateAvailability()) != nil else { return self }
        if stale { result.bookmark = try? result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        return result
    }
    public func relocated(to selected: URL, paths: LauncherPaths) throws -> Self {
        var result = self; result.url = selected.standardizedFileURL.resolvingSymlinksInPath()
        try result.validateAvailability()
        try paths.checkCustomRunDirectory(result, relocatingID: id)
        result.bookmark = try result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return result
    }
    private static func readMarker(_ url: URL) throws -> Marker {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw RuriError.message("无法读取自定义目录身份标记。") }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size >= 0, info.st_size <= 4096 else { throw RuriError.message("自定义目录身份标记无效。") }
        let data = try handle.read(upToCount: 4097) ?? Data()
        guard data.count <= 4096 else { throw RuriError.message("自定义目录标记过大。") }
        let marker = try JSONDecoder().decode(Marker.self, from: data)
        guard marker.version == 1, marker.id != GameDirectory.defaultID else { throw RuriError.message("自定义目录标记版本无效。") }
        return marker
    }
}

extension LauncherPaths {
    func checkCustomRunDirectory(_ selected: CustomRunDirectory, relocatingID: UUID? = nil, readingIdentity: Bool = false) throws {
        try selected.validateConfiguration()
        let target = selected.url.standardizedFileURL.resolvingSymlinksInPath().path
        func overlaps(_ first: String, _ second: String) -> Bool {
            first == second || first.hasPrefix(second == "/" ? "/" : second + "/") || second.hasPrefix(first == "/" ? "/" : first + "/")
        }
        for managed in [root] + directories.map({ $0.isMinecraft ? $0.url.appendingPathComponent(".ruri") : $0.url }) {
            guard !overlaps(target, managed.standardizedFileURL.resolvingSymlinksInPath().path) else { throw RuriError.message("自定义运行目录不能与 Ruri 公共数据或实例文件夹重叠。请使用独立/共享模式，或选择其他位置。") }
        }
        for other in (instanceCustomDirectories ?? [:]).values where other.id != relocatingID {
            let existing = other.url.standardizedFileURL.resolvingSymlinksInPath().path
            if existing == target {
                guard readingIdentity || selected.id == other.id else { throw RuriError.message("同一路径的目录身份已经改变，请重新检查原目录。") }
                continue
            }
            guard selected.id != other.id else { throw RuriError.message("此目录是已登记自定义目录的另一份副本，请重新定位原目录或选择其他目录。") }
            guard !overlaps(target, existing) else { throw RuriError.message("自定义运行目录之间不能相互嵌套。") }
        }
    }
}

extension PersistentState {
    /// All references to one game root must resolve together. Otherwise a
    /// missing bookmark on one instance could split a shared location after a
    /// Finder move and make the whole directory configuration inconsistent.
    public func resolvingCustomRunDirectoryBookmarks() -> Self {
        let locations = instances.sorted { ($0.runDirectory == .custom ? 0 : 1) < ($1.runDirectory == .custom ? 0 : 1) }.compactMap(\.customRunDirectory)
        var resolved: [UUID: CustomRunDirectory] = [:]
        var ambiguous = Set<UUID>()
        for location in locations {
            if (try? location.validateAvailability()) != nil {
                if let existing = resolved[location.id], !existing.isSameLocation(as: location) { ambiguous.insert(location.id) }
                else { resolved[location.id] = location }
            }
        }
        for location in locations where resolved[location.id] == nil {
            let candidate = location.resolvingBookmark()
            if (try? candidate.validateAvailability()) != nil { resolved[location.id] = candidate }
        }
        var state = self
        state.instances = instances.map { item in
            var item = item
            if let id = item.customRunDirectory?.id, !ambiguous.contains(id), let location = resolved[id] { item.customRunDirectory = location }
            return item
        }
        return state
    }
}
