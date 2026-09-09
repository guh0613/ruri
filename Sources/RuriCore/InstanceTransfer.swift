import Foundation

public enum InstanceExportFormat: String, CaseIterable, Sendable, Identifiable {
    case ruri, multimc
    public var id: String { rawValue }
    public var title: String { self == .ruri ? "Ruri 实例" : "Prism / MultiMC" }
}

public struct PreparedInstanceImport: Identifiable, Sendable {
    public let id: UUID
    public let format: String
    public let instance: GameInstance
    public let warnings: [String]
    public let fileCount: Int
    public let byteCount: Int64
    let workspace: URL
    let game: URL
    let records: Data?
}

/// Portable exports contain game data and preferences; shared downloads and
/// machine-specific Java paths are rebuilt for the destination Mac.
struct PortableInstance: Codable {
    var formatVersion = 1
    let name: String
    let gameVersion: String
    let loader: LoaderKind
    let loaderVersion: String?
    let memoryMB: Int
    let extraJVMArguments: String
    let width: Int
    let height: Int
    init(_ instance: GameInstance) {
        name = instance.name; gameVersion = instance.gameVersion; loader = instance.loader; loaderVersion = instance.loaderVersion
        memoryMB = instance.memoryMB; extraJVMArguments = instance.extraJVMArguments; width = instance.width; height = instance.height
    }
    func instance() throws -> GameInstance {
        guard formatVersion == 1 else { throw RuriError.message("此实例包需要更新版本的 Ruri。") }
        var result = GameInstance(name: name, gameVersion: gameVersion, loader: loader, loaderVersion: loaderVersion)
        result.memoryMB = memoryMB; result.extraJVMArguments = extraJVMArguments; result.width = width; result.height = height
        return result
    }
}

struct MultiMCPack: Codable {
    struct Component: Codable { let uid: String; let version: String? }
    var formatVersion = 1
    let components: [Component]
}

public actor InstanceTransfer {
    let paths: LauncherPaths
    static let loaderIDs: [String: LoaderKind] = ["net.fabricmc.fabric-loader": .fabric, "org.quiltmc.quilt-loader": .quilt, "net.minecraftforge": .forge, "net.neoforged": .neoforge]
    static let excluded: Set<String> = ["logs", "crash-reports", "assets", "libraries", "versions", "natives", "webcache", "launcher_accounts.json", "launcher_profiles.json", "usercache.json", "usernamecache.json"]
    public init(paths: LauncherPaths) { self.paths = paths }

    public func prepare(_ source: URL, progress: @Sendable (InstallProgress) -> Void = { _ in }) throws -> PreparedInstanceImport {
        try paths.prepare()
        let workspace = paths.cache.appendingPathComponent("transfer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        do {
            progress(InstallProgress("正在识别实例"))
            let isDirectory = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard isDirectory.isSymbolicLink != true else { throw RuriError.message("请选择实际实例目录或压缩包。") }
            let unpacked: URL
            if isDirectory.isDirectory == true { unpacked = source }
            else {
                unpacked = workspace.appendingPathComponent("unpacked")
                try SafeArchive.extract(source, to: unpacked, maxBytes: 128 * 1024 * 1024 * 1024)
            }
            let root = try Self.findRoot(unpacked)
            let description = try Self.describe(root)
            let locks = try Self.lockWorlds(description.game); defer { locks.forEach { close($0) } }
            let snapshot = workspace.appendingPathComponent("minecraft")
            let excluded = try Self.exclusions(description.game, includeWorlds: true)
            try FileTree.copy(from: description.game, to: snapshot, excluding: excluded) { done, total in progress(InstallProgress("正在复制实例内容", completed: done, total: total)) }
            let entries = try FileTree.entries(in: snapshot)
            return PreparedInstanceImport(id: UUID(), format: description.format, instance: description.instance, warnings: description.warnings,
                                          fileCount: entries.filter { !$0.directory }.count, byteCount: entries.reduce(0) { $0 + $1.size }, workspace: workspace, game: snapshot, records: description.records)
        } catch { try? FileManager.default.removeItem(at: workspace); throw error }
    }

    public func discard(_ prepared: PreparedInstanceImport) { try? FileManager.default.removeItem(at: prepared.workspace) }

    public func install(_ prepared: PreparedInstanceImport, name: String, importJVMArguments: Bool = false, installer: GameInstaller, concurrency: Int = 8,
                        progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> GameInstance {
        try await install(prepared, name: name, importJVMArguments: importJVMArguments) { instance in
            try await installer.install(instance, concurrency: concurrency, progress: progress)
        }
    }
    // The closure makes filesystem rollback testable without contacting game services.
    func install(_ prepared: PreparedInstanceImport, name: String, importJVMArguments: Bool = false,
                 installGame: @Sendable (GameInstance) async throws -> GameInstance) async throws -> GameInstance {
        var instance = prepared.instance
        instance.id = UUID(); instance.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if instance.name.isEmpty { instance.name = prepared.instance.name }
        instance.javaPath = nil; instance.installed = false
        if !importJVMArguments { instance.extraJVMArguments = "" }
        try Self.validate(instance)
        do {
            // User files are copied first; official installer then supplies any
            // generated legacy resources without a destructive directory merge.
            try FileTree.copy(from: prepared.game, to: paths.game(instance.id))
            if let records = prepared.records {
                try records.write(to: paths.instance(instance.id).appendingPathComponent("content.json"), options: .atomic)
                _ = try await ContentManager(paths: paths, instanceID: instance.id).records()
            }
            instance = try await installGame(instance)
            try Task.checkCancellation()
            return instance
        } catch { try? FileManager.default.removeItem(at: paths.instance(instance.id)); throw error }
    }

    public func export(_ instance: GameInstance, to destination: URL, format: InstanceExportFormat = .ruri, includeWorlds: Bool = true,
                       progress: @Sendable (InstallProgress) -> Void = { _ in }) async throws {
        try await ContentManager(paths: paths, instanceID: instance.id).recover()
        try await WorldManager(paths: paths, instanceID: instance.id).recover()
        let game = paths.game(instance.id)
        let locks = try Self.lockWorlds(game); defer { locks.forEach { close($0) } }
        var extra: [String: Data] = [:]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if format == .ruri {
            extra["ruri-instance.json"] = try encoder.encode(PortableInstance(instance))
            let records = try await ContentManager(paths: paths, instanceID: instance.id).records()
            extra["ruri-content.json"] = try encoder.encode(records)
        } else {
            var components = [MultiMCPack.Component(uid: "net.minecraft", version: instance.gameVersion)]
            if instance.loader != .vanilla, let uid = Self.loaderIDs.first(where: { $0.value == instance.loader })?.key {
                components.append(.init(uid: uid, version: instance.loaderVersion))
            }
            extra["mmc-pack.json"] = try encoder.encode(MultiMCPack(components: components))
            let cfg = ["InstanceType=OneSix", "name=\(Self.iniEncode(instance.name))", "OverrideMemory=true", "MaxMemAlloc=\(instance.memoryMB)",
                       "OverrideWindow=true", "MinecraftWinWidth=\(instance.width)", "MinecraftWinHeight=\(instance.height)",
                       "OverrideJavaArgs=\(!instance.extraJVMArguments.isEmpty)", "JvmArgs=\(Self.iniEncode(instance.extraJVMArguments))"].joined(separator: "\n") + "\n"
            extra["instance.cfg"] = Data(cfg.utf8)
        }
        progress(InstallProgress("正在导出实例"))
        try SafeArchive.create(from: game, to: destination, prefix: format == .ruri ? "minecraft" : ".minecraft", additionalFiles: extra,
                               excluding: Self.exclusions(game, includeWorlds: includeWorlds)) { done, total in progress(InstallProgress("正在导出实例", completed: done, total: total)) }
    }

    private static func findRoot(_ source: URL) throws -> URL {
        func recognized(_ dir: URL) -> Bool { ["ruri-instance.json", "mmc-pack.json"].contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) } }
        if recognized(source) { return source }
        let candidates = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]).filter {
            let info = try $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return info.isDirectory == true && info.isSymbolicLink != true && recognized($0)
        }
        guard candidates.count == 1 else { throw RuriError.message(candidates.isEmpty ? "未找到实例清单。请选择 Ruri 导出包，或含 mmc-pack.json 的 Prism/MultiMC 实例。" : "目录包含多个实例，请选择其中一个实例目录。") }
        return candidates[0]
    }
    private static func read(_ url: URL) throws -> Data {
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? 0) <= 4 * 1024 * 1024 else { throw RuriError.message("实例清单不是有效文件：\(url.lastPathComponent)") }
        return try Data(contentsOf: url)
    }
    static func describe(_ root: URL) throws -> (instance: GameInstance, game: URL, format: String, warnings: [String], records: Data?) {
        let fm = FileManager.default
        let portable = root.appendingPathComponent("ruri-instance.json")
        var instance: GameInstance; var warnings: [String] = []; let format: String; var records: Data?
        if fm.fileExists(atPath: portable.path) {
            instance = try JSONDecoder().decode(PortableInstance.self, from: read(portable)).instance(); format = "Ruri"
            let metadata = root.appendingPathComponent("ruri-content.json")
            if fm.fileExists(atPath: metadata.path) { records = try read(metadata) }
        } else {
            format = "Prism / MultiMC"
            let pack = try JSONDecoder().decode(MultiMCPack.self, from: read(root.appendingPathComponent("mmc-pack.json")))
            guard pack.formatVersion == 1, Set(pack.components.map(\.uid)).count == pack.components.count,
                  let game = pack.components.first(where: { $0.uid == "net.minecraft" })?.version else { throw RuriError.message("MultiMC 实例清单无效或缺少 Minecraft 版本。") }
            let supported = Set(loaderIDs.keys).union(["net.minecraft", "org.lwjgl", "org.lwjgl3", "net.fabricmc.intermediary", "org.quiltmc.hashed"])
            let unknown = Set(pack.components.map(\.uid)).subtracting(supported)
            guard unknown.isEmpty else { throw RuriError.message("此实例包含尚未支持的组件：\(unknown.sorted().joined(separator: ", "))") }
            let loaders = pack.components.filter { loaderIDs[$0.uid] != nil }
            guard loaders.count <= 1 else { throw RuriError.message("实例同时声明了多个加载器，暂时无法迁移。") }
            for folder in ["patches", "jarmods"] {
                let url = root.appendingPathComponent(folder)
                if fm.fileExists(atPath: url.path), !(try FileTree.entries(in: url)).isEmpty { throw RuriError.message("实例包含自定义 \(folder)，需要先处理这些补丁后再迁移。") }
            }
            let cfgURL = root.appendingPathComponent("instance.cfg")
            let cfg = fm.fileExists(atPath: cfgURL.path) ? try iniDecode(String(decoding: read(cfgURL), as: UTF8.self)) : [:]
            instance = GameInstance(name: cfg["name"] ?? root.lastPathComponent, gameVersion: game, loader: loaders.first.flatMap { loaderIDs[$0.uid] } ?? .vanilla, loaderVersion: loaders.first?.version)
            if cfg["OverrideMemory"]?.lowercased() == "true", let value = cfg["MaxMemAlloc"].flatMap(Int.init) { instance.memoryMB = value }
            if cfg["OverrideWindow"]?.lowercased() == "true" {
                instance.width = cfg["MinecraftWinWidth"].flatMap(Int.init) ?? instance.width; instance.height = cfg["MinecraftWinHeight"].flatMap(Int.init) ?? instance.height
            }
            if cfg["OverrideJavaArgs"]?.lowercased() == "true" { instance.extraJVMArguments = cfg["JvmArgs"] ?? "" }
            if ["PreLaunchCommand", "PostExitCommand", "WrapperCommand"].contains(where: { !(cfg[$0] ?? "").isEmpty }) { warnings.append("原实例的启动前、退出后或包装命令不会执行。需要这些命令的整合包可能需要额外设置。") }
            if cfg["LaunchMaximized"]?.lowercased() == "true" { warnings.append("窗口将使用所选分辨率；进入游戏后可切换全屏。") }
        }
        try validate(instance)
        let games = ["minecraft", ".minecraft"].map { root.appendingPathComponent($0) }.filter { fm.fileExists(atPath: $0.path) }
        guard games.count == 1, try games[0].resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
              try games[0].resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message("实例需要唯一的 minecraft 或 .minecraft 游戏目录。") }
        if !instance.extraJVMArguments.isEmpty { warnings.append("实例带有自定义 JVM 参数，确认内容后可选择保留。") }
        return (instance, games[0], format, warnings, records)
    }
    private static func validate(_ instance: GameInstance) throws {
        guard !instance.name.isEmpty, instance.name.count <= 256, !instance.gameVersion.isEmpty, instance.gameVersion.count <= 128,
              instance.loader == .vanilla || !(instance.loaderVersion ?? "").isEmpty,
              (512...262144).contains(instance.memoryMB), (320...16384).contains(instance.width), (240...16384).contains(instance.height),
              instance.extraJVMArguments.count <= 32768 else { throw RuriError.message("实例版本、内存或窗口设置无效。") }
    }
    private static func exclusions(_ game: URL, includeWorlds: Bool) throws -> Set<String> {
        var result = excluded
        if !includeWorlds { result.insert("saves") }
        let saves = game.appendingPathComponent("saves")
        if FileManager.default.fileExists(atPath: saves.path) {
            for world in try FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: nil) { result.insert("saves/\(world.lastPathComponent)/session.lock") }
        }
        return result
    }
    private static func lockWorlds(_ game: URL) throws -> [Int32] {
        let saves = game.appendingPathComponent("saves")
        guard FileManager.default.fileExists(atPath: saves.path) else { return [] }
        guard try saves.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw RuriError.message("存档目录不能是符号链接。") }
        var locks: [Int32] = []
        do {
            for world in try FileManager.default.contentsOfDirectory(at: saves, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let info = try world.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard info.isSymbolicLink != true else { throw RuriError.message("存档包含符号链接。") }
                if info.isDirectory == true, let lock = try WorldManager.readLock(world) { locks.append(lock) }
            }
            return locks
        } catch { locks.forEach { close($0) }; throw error }
    }
    static func iniEncode(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    static func iniDecode(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix(";"), !trimmed.hasPrefix("["), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { value.removeFirst(); value.removeLast() }
            var decoded = ""; var escape = false
            for char in value {
                if escape { decoded += char == "n" ? "\n" : char == "r" ? "\r" : char == "t" ? "\t" : String(char); escape = false }
                else if char == "\\" { escape = true } else { decoded.append(char) }
            }
            if escape { decoded.append("\\") }
            result[key] = decoded
        }
        return result
    }
}
