import Foundation
import Darwin

public struct SchematicEntry: Identifiable, Sendable {
    public let id: String
    public let url: URL
    public let isDirectory: Bool
    public let size: Int64
    public let modifiedAt: Date?
    public var name: String { url.lastPathComponent }
}

public struct SchematicInfo: Sendable {
    public let name: String?
    public let author: String?
    public let description: String?
    public let dimensions: [Int64]
    public let blocks: Int64?
    public let volume: Int64?
    public let regions: Int?
    public let formatVersion: Int64?
    public let gameDataVersion: Int64?
    public let createdAt: Date?
    public let modifiedAt: Date?
    public let previewARGB: Data?
}

public actor SchematicManager {
    public static let fileExtensions = ["litematic", "schem", "schematic", "nbt"]
    private let paths: LauncherPaths
    private let instanceID: UUID
    private static let diskLock = NSRecursiveLock()
    private let locationLock = InstanceLocationOperationLock()
    private let operationLock = GameDataOperationLock()
    private var root: URL { paths.game(instanceID).appendingPathComponent("schematics") }
    public init(paths: LauncherPaths, instanceID: UUID) { self.paths = paths; self.instanceID = instanceID }

    public func list(directory: String = "") throws -> [SchematicEntry] {
        try withLock {
            let folder = try path(directory)
            guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
            return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles]).compactMap { file in
                let info = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard info.isSymbolicLink != true, info.isDirectory == true || info.isRegularFile == true && Self.fileExtensions.contains(file.pathExtension.lowercased()) else { return nil }
                return SchematicEntry(id: directory.isEmpty ? file.lastPathComponent : directory + "/" + file.lastPathComponent, url: file, isDirectory: info.isDirectory == true, size: Int64(info.fileSize ?? 0), modifiedAt: info.contentModificationDate)
            }.sorted { $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    public func createFolder(_ name: String, directory: String = "") throws {
        try withLock {
            try validateName(name)
            let parent = try path(directory), destination = try path(directory.isEmpty ? name : directory + "/" + name)
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw RuriError.message("同名文件或文件夹已存在。") }
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        }
    }
    public func importFiles(_ sources: [URL], directory: String = "") throws {
        try withLock {
            guard !sources.isEmpty, sources.count <= 200 else { throw RuriError.message("请选择 1–200 个原理图文件。") }
            let parent = try path(directory)
            var targets: [URL] = [], names = Set<String>()
            for source in sources {
                try validateName(source.lastPathComponent)
                let info = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, Self.fileExtensions.contains(source.pathExtension.lowercased()) else { throw RuriError.message("请选择 litematic、schem、schematic 或 nbt 原理图文件。") }
                let target = parent.appendingPathComponent(source.lastPathComponent)
                guard names.insert(source.lastPathComponent.lowercased()).inserted, !FileManager.default.fileExists(atPath: target.path), (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) == nil else {
                    throw RuriError.message("同名原理图已存在：\(source.lastPathComponent)。请先改名或移走旧文件。")
                }
                targets.append(target)
            }
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let staging = parent.appendingPathComponent(".ruri-import-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: staging) }
            for source in sources {
                try Task.checkCancellation()
                try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
            }
            try Task.checkCancellation()
            var published: [URL] = []
            do {
                for target in targets {
                    try FileManager.default.moveItem(at: staging.appendingPathComponent(target.lastPathComponent), to: target)
                    published.append(target)
                }
            } catch { for target in published { try FileManager.default.removeItem(at: target) }; throw error }
        }
    }
    public func export(_ entry: SchematicEntry, to destination: URL) throws {
        try withLock {
            let source = try checked(entry)
            guard !entry.isDirectory else { throw RuriError.message("请选择单个原理图文件导出。") }
            guard source.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else { throw RuriError.message("导出位置与原文件相同。") }
            let staging = destination.deletingLastPathComponent().appendingPathComponent(".ruri-export-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            try Task.checkCancellation()
            guard rename(staging.path, destination.path) == 0 else { throw RuriError.message("无法保存导出的原理图。") }
        }
    }
    @discardableResult public func remove(_ entry: SchematicEntry) throws -> URL? {
        try withLock {
            let source = try checked(entry)
            var result: NSURL?
            try FileManager.default.trashItem(at: source, resultingItemURL: &result)
            return result as URL?
        }
    }
    public func info(_ entry: SchematicEntry) throws -> SchematicInfo {
        try withLock {
            let file = try checked(entry)
            guard !entry.isDirectory else { throw RuriError.message("文件夹没有原理图信息。") }
            var reader = try NBTReader(data: RunDirectoryCopyGuard.read(file, limit: 32 * 1024 * 1024))
            let raw = try reader.read(), root = raw["Schematic"] ?? raw, metadata = root["Metadata"]
            let size: [Int64]
            if let enclosing = metadata?["EnclosingSize"] { size = ["x", "y", "z"].compactMap { enclosing[$0]?.integer } }
            else if case .list(let list) = root["size"] { size = list.compactMap(\.integer) }
            else { size = ["Width", "Height", "Length"].compactMap { root[$0]?.integer.map { Int64(UInt16(truncatingIfNeeded: $0)) } } }
            let regions: Int?
            if case .compound(let values) = root["Regions"] { regions = values.count } else { regions = nil }
            let preview: Data?
            if case .array(let data) = metadata?["PreviewImageData"], data.count <= 4 * 1024 * 1024 { preview = data } else { preview = nil }
            func date(_ value: NBTValue?) -> Date? { value?.integer.map { Date(timeIntervalSince1970: Double($0) / 1000) } }
            return SchematicInfo(name: metadata?["Name"]?.string, author: metadata?["Author"]?.string ?? root["author"]?.string,
                                 description: metadata?["Description"]?.string, dimensions: size.count == 3 ? size : [], blocks: metadata?["TotalBlocks"]?.integer,
                                 volume: metadata?["TotalVolume"]?.integer, regions: regions, formatVersion: root["Version"]?.integer,
                                 gameDataVersion: root["MinecraftDataVersion"]?.integer ?? root["DataVersion"]?.integer,
                                 createdAt: date(metadata?["TimeCreated"] ?? metadata?["Date"]), modifiedAt: date(metadata?["TimeModified"]), previewARGB: preview)
        }
    }
    private func checked(_ entry: SchematicEntry) throws -> URL {
        let file = try path(entry.id), info = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        guard file.standardizedFileURL == entry.url.standardizedFileURL, entry.isDirectory ? info.isDirectory == true : info.isRegularFile == true else { throw RuriError.message("原理图文件已改变，请刷新列表。") }
        return file
    }
    private func validateName(_ name: String) throws {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"), !name.contains("\0") else { throw RuriError.message("请输入有效的文件或文件夹名称。") }
    }
    private func path(_ relative: String) throws -> URL {
        var current = root
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) == nil else { throw RuriError.message("原理图管理不修改符号链接目录。") }
        if relative.isEmpty { return current }
        for part in relative.split(separator: "/", omittingEmptySubsequences: false) {
            try validateName(String(part)); current.appendPathComponent(String(part))
            guard (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) == nil else { throw RuriError.message("原理图管理不修改符号链接。") }
        }
        return try LauncherPaths.safePath(relative, within: root)
    }
    private func withLock<T>(_ action: () throws -> T) throws -> T {
        Self.diskLock.lock(); defer { Self.diskLock.unlock() }
        try locationLock.acquire(paths: paths, instanceID: instanceID); defer { locationLock.release() }
        try paths.validateInstanceLocation(instanceID)
        try RunDirectoryCopyGuard.requireAvailable(paths: paths, instanceID: instanceID)
        try operationLock.acquire(directory: paths.gameDataState(instanceID), name: ".schematic-operation.lock"); defer { operationLock.release() }
        return try action()
    }
}
