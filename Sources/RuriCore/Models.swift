import Foundation
import CryptoKit

public enum RuriError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

public enum LoaderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case vanilla, fabric, quilt, forge, neoforge
    public var id: String { rawValue }
    public var title: String { switch self { case .vanilla: "原版"; case .fabric: "Fabric"; case .quilt: "Quilt"; case .forge: "Forge"; case .neoforge: "NeoForge" } }
    public var symbol: String { switch self { case .vanilla: "cube.fill"; case .fabric: "square.stack.3d.up.fill"; case .quilt: "square.grid.3x3.fill"; case .forge: "hammer.fill"; case .neoforge: "flame.fill" } }
    public var usesInstaller: Bool { self == .forge || self == .neoforge }
}

public struct GameInstance: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var gameVersion: String
    public var loader: LoaderKind
    public var loaderVersion: String?
    public var createdAt: Date
    public var lastPlayed: Date?
    public var playTime: TimeInterval
    public var memoryMB: Int
    public var javaPath: String?
    public var extraJVMArguments: String
    public var extraGameArguments: String?
    public var supportedJavaMajors: [Int]?
    public var packLibraries: [Library]?
    public var width: Int
    public var height: Int
    public var favorite: Bool
    public var installed: Bool
    public init(name: String, gameVersion: String, loader: LoaderKind = .vanilla, loaderVersion: String? = nil) {
        id = UUID(); self.name = name; self.gameVersion = gameVersion; self.loader = loader
        self.loaderVersion = loaderVersion; createdAt = Date(); playTime = 0
        memoryMB = 4096; extraJVMArguments = ""; width = 1280; height = 800; favorite = false; installed = false
    }
    public func preferredJavaMajor(default minimum: Int) throws -> Int {
        guard let supported = supportedJavaMajors, !supported.isEmpty else { return minimum }
        guard let selected = supported.filter({ $0 >= minimum }).sorted(by: { a, b in a == minimum || b != minimum && a < b }).first else { throw RuriError.message("整合包指定的 Java 版本与游戏要求的 Java \(minimum) 不兼容。") }
        return selected
    }
    public var subtitle: String { loader == .vanilla ? "Minecraft \(gameVersion)" : "\(gameVersion) · \(loader.title) \(loaderVersion ?? "")" }
}

public struct Account: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case offline, microsoft }
    public var id: UUID
    public var kind: Kind
    public var username: String
    public var uuid: String
    public init(username: String) throws {
        guard username.range(of: "^[A-Za-z0-9_]{3,16}$", options: .regularExpression) != nil else {
            throw RuriError.message("玩家名需为 3–16 位英文字母、数字或下划线。")
        }
        self.id = UUID(); self.kind = .offline; self.username = username
        var bytes = Array(Insecure.MD5.hash(data: Data("OfflinePlayer:\(username)".utf8)))
        bytes[6] = (bytes[6] & 0x0f) | 0x30; bytes[8] = (bytes[8] & 0x3f) | 0x80
        uuid = bytes.map { String(format: "%02x", $0) }.joined()
    }
    public init(id: UUID = UUID(), username: String, uuid: String, kind: Kind) {
        self.id = id; self.username = username; self.uuid = uuid; self.kind = kind
    }
}

public struct AppSettings: Codable, Sendable {
    public var concurrentDownloads = 8
    public var microsoftClientID = ""
    public var showSnapshots = false
    public var defaultMemoryMB = 4096
    public var appearance = "system"
    public var downloadSource: DownloadSource?
    public init() {}
}

public struct PersistentState: Codable, Sendable {
    public var schemaVersion = 1
    public var instances: [GameInstance] = []
    public var accounts: [Account] = []
    public var activeAccountID: UUID?
    public var selectedInstanceID: UUID?
    public var settings = AppSettings()
    public init() {}
}

public struct InstallProgress: Sendable {
    public var stage: String
    public var completed: Int
    public var total: Int
    public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    public init(_ stage: String, completed: Int = 0, total: Int = 0) {
        self.stage = stage; self.completed = completed; self.total = total
    }
}

public struct LauncherPaths: Sendable {
    public let root: URL
    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Ruri", isDirectory: true)
    }
    public var libraries: URL { root.appendingPathComponent("libraries") }
    public var assets: URL { root.appendingPathComponent("assets") }
    public var versions: URL { root.appendingPathComponent("versions") }
    public var instances: URL { root.appendingPathComponent("instances") }
    public var runtimes: URL { root.appendingPathComponent("runtimes") }
    public var cache: URL { root.appendingPathComponent("cache") }
    public var state: URL { root.appendingPathComponent("state.json") }
    public func instance(_ id: UUID) -> URL { instances.appendingPathComponent(id.uuidString) }
    public func game(_ id: UUID) -> URL { instance(id).appendingPathComponent("minecraft") }
    public func manifest(_ id: UUID) -> URL { instance(id).appendingPathComponent("version.json") }
    public func prepare() throws {
        for url in [root, libraries, assets, versions, instances, runtimes, cache] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    }
    public static func safePath(_ path: String, within root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              !path.split(separator: "/").contains("..") else { throw RuriError.message("不安全的文件路径：\(path)") }
        let baseURL = root.standardizedFileURL.resolvingSymlinksInPath()
        let base = baseURL.path + "/"
        var resolved = baseURL
        // Foundation does not resolve an intermediate symlink reliably when the
        // final file does not exist yet. Validate each existing prefix instead.
        for component in path.split(separator: "/") where component != "." {
            resolved = resolved.appendingPathComponent(String(component)).standardizedFileURL
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: resolved.path)) != nil {
                resolved = resolved.resolvingSymlinksInPath()
            }
            guard resolved.path.hasPrefix(base) else { throw RuriError.message("文件路径超出实例目录：\(path)") }
        }
        return resolved
    }
}

public enum StateStore {
    public static func load(_ paths: LauncherPaths) throws -> PersistentState {
        guard FileManager.default.fileExists(atPath: paths.state.path) else { return PersistentState() }
        let data = try Data(contentsOf: paths.state)
        let result = try JSONDecoder().decode(PersistentState.self, from: data)
        guard result.schemaVersion == 1 else { throw RuriError.message("此数据由更新版本的 Ruri 创建，请升级启动器。") }
        return result
    }
    public static func save(_ state: PersistentState, to paths: LauncherPaths) throws {
        try paths.prepare()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: paths.state, options: .atomic)
    }
}
