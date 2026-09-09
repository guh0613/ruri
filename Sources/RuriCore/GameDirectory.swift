import Foundation

/// A collection of managed instances. Shared downloads and accounts stay in
/// LauncherPaths.root; moving or disconnecting a collection never changes them.
public struct GameDirectory: Codable, Identifiable, Equatable, Sendable {
    public static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    public let id: UUID
    public var name: String
    public var url: URL
    public var bookmark: Data?
    public let createdAt: Date
    static let markerName = ".ruri-directory.json"
    struct Marker: Codable { let schema: Int; let id: UUID }

    /// Registration is deliberate and only initializes an empty selected folder.
    /// Existing launcher layouts need an import preview, not a silent conversion.
    public static func create(name: String, at url: URL, paths: LauncherPaths) throws -> GameDirectory {
        let directory = GameDirectory(id: UUID(), name: try validName(name), url: url.standardizedFileURL.resolvingSymlinksInPath(), bookmark: nil, createdAt: Date())
        try paths.checkNewDirectory(directory)
        let entries = try FileManager.default.contentsOfDirectory(at: directory.url, includingPropertiesForKeys: nil)
        if entries.contains(where: { $0.lastPathComponent == markerName }) {
            let markerURL = directory.url.appendingPathComponent(markerName)
            let values = try markerURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1024,
                  entries.allSatisfy({ [markerName, ".DS_Store", "instances"].contains($0.lastPathComponent) }) else { throw RuriError.message("此文件夹已有数据，请通过实例导入入口处理。") }
            let marker = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: markerURL))
            guard !paths.directories.contains(where: { $0.id == marker.id }), marker.id != defaultID else { throw RuriError.message("此实例文件夹已经登记，不能重复添加其副本。") }
            let instances = directory.url.appendingPathComponent("instances")
            if FileManager.default.fileExists(atPath: instances.path) {
                guard try instances.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                      try FileManager.default.contentsOfDirectory(atPath: instances.path).allSatisfy({ $0 == ".DS_Store" }) else { throw RuriError.message("此文件夹仍有实例文件，请通过导入入口预览后导入。") }
            }
            var existing = GameDirectory(id: marker.id, name: directory.name, url: directory.url, bookmark: nil, createdAt: Date())
            try existing.validateAvailability()
            existing.bookmark = try existing.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            return existing
        }
        guard entries.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else {
            throw RuriError.message("请选择空文件夹作为新的实例文件夹。已有启动器目录请通过导入入口预览后导入，原文件不会被覆盖。")
        }
        var result = directory
        result.bookmark = try directory.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        try JSONEncoder().encode(Marker(schema: 1, id: directory.id)).write(to: directory.url.appendingPathComponent(markerName), options: .withoutOverwriting)
        return result
    }

    public func validateAvailability() throws {
        do {
            guard url.isFileURL, try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message("路径不是文件夹") }
            let marker = url.appendingPathComponent(Self.markerName)
            let values = try marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? .max) <= 1024 else { throw RuriError.message("目录标记无效") }
            let record = try JSONDecoder().decode(Marker.self, from: Data(contentsOf: marker))
            guard record.schema == 1, record.id == id else { throw RuriError.message("目录身份与登记信息不一致") }
        } catch {
            throw RuriError.message("无法访问实例文件夹“\(name)”：\(url.path)\n请连接磁盘、检查访问权限或重新定位原文件夹。\n\(error.localizedDescription)")
        }
    }

    /// Resolve Finder moves without UI or mounting an absent volume. Identity
    /// validation prevents a new folder at an old mount point from replacing it.
    public func resolvingBookmark() -> GameDirectory {
        guard let bookmark else { return self }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale) else { return self }
        var result = self; result.url = resolved.standardizedFileURL.resolvingSymlinksInPath()
        guard (try? result.validateAvailability()) != nil else { return self }
        if stale { result.bookmark = try? result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) }
        return result
    }

    public func relocated(to url: URL, paths: LauncherPaths) throws -> GameDirectory {
        var result = self; result.url = url.standardizedFileURL.resolvingSymlinksInPath()
        try result.validateAvailability()
        try paths.checkNewDirectory(result)
        result.bookmark = try result.url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return result
    }

    public static func validName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 100, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw RuriError.message("文件夹名称需为 1–100 个字符。") }
        return name
    }
}

extension LauncherPaths {
    public func configured(with state: PersistentState) -> LauncherPaths {
        LauncherPaths(root: root, directories: state.gameDirectories ?? [],
                      instanceDirectories: state.instances.reduce(into: [:]) { $0[$1.id] = $1.directoryID ?? GameDirectory.defaultID },
                      newInstanceDirectoryID: state.selectedDirectoryID ?? GameDirectory.defaultID)
    }
    public func directoryID(for instanceID: UUID) -> UUID { instanceDirectories[instanceID] ?? newInstanceDirectoryID }
    public func directoryRoot(_ id: UUID) -> URL {
        if id == GameDirectory.defaultID { return root }
        // Invalid references must never silently become the default directory.
        return directories.first(where: { $0.id == id })?.url ?? root.appendingPathComponent("unavailable-directories/\(id.uuidString)")
    }
    public func validateDirectoryConfiguration() throws {
        let ids = directories.map(\.id)
        guard root.isFileURL, Set(ids).count == ids.count, !ids.contains(GameDirectory.defaultID), directories.count <= 100,
              Set(instanceDirectories.values).union([newInstanceDirectoryID]).subtracting([GameDirectory.defaultID]).isSubset(of: Set(ids)) else { throw RuriError.message("实例文件夹登记信息无效，已暂停操作以保护原数据。") }
        for directory in directories {
            _ = try GameDirectory.validName(directory.name)
            guard directory.url.isFileURL, directory.url.path.hasPrefix("/"), (directory.bookmark?.count ?? 0) <= 1_048_576 else { throw RuriError.message("实例文件夹位置无效。") }
            try checkDirectoryOverlap(directory)
        }
    }
    func checkNewDirectory(_ directory: GameDirectory) throws {
        guard directory.url.isFileURL, try directory.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw RuriError.message("请选择已存在的本地文件夹。") }
        try checkDirectoryOverlap(directory)
    }
    private func checkDirectoryOverlap(_ directory: GameDirectory) throws {
        let target = directory.url.standardizedFileURL.resolvingSymlinksInPath().path
        for other in [root] + directories.filter({ $0.id != directory.id }).map(\.url) {
            let existing = other.standardizedFileURL.resolvingSymlinksInPath().path
            guard target != existing, !target.hasPrefix(existing + "/"), !existing.hasPrefix(target == "/" ? "/" : target + "/") else {
                throw RuriError.message("实例文件夹不能与已登记文件夹或公共数据目录重叠。")
            }
        }
    }
    public func validateInstanceLocation(_ instanceID: UUID) throws {
        let id = directoryID(for: instanceID)
        if id == GameDirectory.defaultID { return }
        guard let directory = directories.first(where: { $0.id == id }) else { throw RuriError.message("找不到实例所属文件夹，请恢复目录登记后重试。") }
        try directory.validateAvailability()
        // The selected directory is trusted; its internal managed tree may not
        // escape through a symlink, including one with a not-yet-created leaf.
        _ = try Self.safePath("instances/\(instanceID.uuidString)/minecraft", within: directory.url)
    }
    public func prepareInstance(_ instanceID: UUID) throws {
        try validateInstanceLocation(instanceID)
        try FileManager.default.createDirectory(at: instance(instanceID), withIntermediateDirectories: true)
    }
    /// Freeze exactly one instance's location for a detached monitor. Bookmarks
    /// are only for the launcher UI; the monitor must retain the launch path.
    func monitorSnapshot(for instanceID: UUID) -> LauncherPaths {
        let id = directoryID(for: instanceID)
        let selected = directories.filter { $0.id == id }.map { item in var item = item; item.bookmark = nil; return item }
        return LauncherPaths(root: root, directories: selected, instanceDirectories: [instanceID: id])
    }
}
