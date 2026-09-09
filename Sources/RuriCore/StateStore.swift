import Foundation
import Darwin

public enum StateStore {
    public static func load(_ paths: LauncherPaths) throws -> PersistentState {
        guard FileManager.default.fileExists(atPath: paths.state.path) else { return PersistentState() }
        let result = try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: paths.state))
        guard (1...6).contains(result.schemaVersion) else { throw RuriError.message("此数据由更新版本的 Ruri 创建，请升级启动器。") }
        try validate(result, paths: paths)
        return result
    }

    /// Compare-and-swap by default. A known baseline also permits disjoint
    /// edits from another client, without overwriting its accounts or instances.
    @discardableResult public static func save(_ state: PersistentState, to paths: LauncherPaths, basedOn baseline: PersistentState? = nil) throws -> PersistentState {
        let fd = try acquire(paths); defer { close(fd) }
        let current = try load(paths)
        let result: PersistentState
        if current.revision == state.revision { result = state }
        else {
            guard let baseline, baseline.revision == state.revision else { throw conflict("数据已由另一个 Ruri 更新") }
            result = try merge(base: baseline, local: state, remote: current)
        }
        return try write(result, paths: paths)
    }

    /// A small synchronous mutation of the latest state under one process lock.
    /// No downloads or external processes belong inside this closure.
    @discardableResult public static func update(_ paths: LauncherPaths, _ mutation: (inout PersistentState) throws -> Void) throws -> PersistentState {
        let fd = try acquire(paths); defer { close(fd) }
        var state = try load(paths)
        try mutation(&state)
        return try write(state, paths: paths)
    }
    private static func validate(_ state: PersistentState, paths: LauncherPaths) throws {
        guard state.instances.allSatisfy({ $0.frozenMemory == nil }) else { throw RuriError.message("启动快照不能覆盖实例设置，请保存原实例的覆盖项。") }
        guard Set(state.instances.map(\.id)).count == state.instances.count, Set(state.accounts.map(\.id)).count == state.accounts.count else { throw RuriError.message("数据包含重复实例或账号，已暂停写入。") }
        try paths.configured(with: state).validateDirectoryConfiguration()
    }
    private static func write(_ input: PersistentState, paths: LauncherPaths) throws -> PersistentState {
        var state = input; state.schemaVersion = 6; state.revision = UUID()
        try validate(state, paths: paths)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: paths.state, options: [.atomic])
        return state
    }
    private static func acquire(_ paths: LauncherPaths) throws -> Int32 {
        try paths.prepare()
        let file = try LauncherPaths.safePath(".ruri-state.lock", within: paths.root)
        let fd = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RuriError.message("无法锁定 Ruri 设置文件。") }
        var info = stat(), lock = flock(); lock.l_type = Int16(F_WRLCK); lock.l_whence = Int16(SEEK_SET)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, fcntl(fd, F_OFD_SETLK, &lock) == 0 else {
            close(fd); throw RuriError.message("另一个 Ruri 正在保存数据，请稍后重试。")
        }
        return fd
    }
    private static func conflict(_ field: String) -> RuriError {
        let parts = field.split(separator: ".").map(String.init)
        let labels = ["instances": "同一实例", "accounts": "同一账号", "gameDirectories": "同一实例文件夹", "settings": "启动器设置",
                      "name": "名称", "favorite": "收藏状态", "memoryMB": "内存", "defaultMemoryMB": "默认内存", "javaPath": "Java 选择",
                      "width": "窗口宽度", "height": "窗口高度", "appearance": "外观", "downloadSource": "下载源",
                      "extraJVMArguments": "JVM 参数", "extraGameArguments": "游戏参数", "directoryID": "所属文件夹"]
        let description: String
        if let first = parts.first, let subject = labels[first] {
            description = subject + (parts.count > 1 ? "的修改" : "") + "与另一窗口冲突" + (parts.last.flatMap { labels[$0] }.map { "（\($0)）" } ?? "")
        } else if ["selectedInstanceID", "selectedDirectoryID", "activeAccountID"].contains(field) { description = "当前实例、文件夹或账号的选择已在另一窗口改变" }
        else { description = field }
        return .message("保存冲突：\(description)。原文件已保留，请重新载入后再修改。")
    }

    private static func merge(base: PersistentState, local: PersistentState, remote: PersistentState) throws -> PersistentState {
        func object(_ state: PersistentState) throws -> [String: Any] {
            guard var result = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any] else { throw conflict("数据格式无效") }
            result.removeValue(forKey: "revision"); result.removeValue(forKey: "schemaVersion")
            return result
        }
        var merged = try mergeObject(base: object(base), local: object(local), remote: object(remote), path: "")
        merged["schemaVersion"] = 2
        return try JSONDecoder().decode(PersistentState.self, from: JSONSerialization.data(withJSONObject: merged))
    }
    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        if a == nil && b == nil { return true }
        guard let a = a as? NSObject, let b = b as? NSObject else { return false }
        return a.isEqual(b)
    }
    private static func mergeObject(base: [String: Any], local: [String: Any], remote: [String: Any], path: String) throws -> [String: Any] {
        var result: [String: Any] = [:]
        for key in Set(base.keys).union(local.keys).union(remote.keys) {
            let b = base[key], l = local[key], r = remote[key]
            let field = path.isEmpty ? key : path + "." + key
            if equal(l, b) { result[key] = r }
            else if equal(r, b) || equal(l, r) { result[key] = l }
            else if let b = b as? [String: Any], let l = l as? [String: Any], let r = r as? [String: Any] {
                result[key] = try mergeObject(base: b, local: l, remote: r, path: field)
            } else if path.isEmpty && ["instances", "accounts", "gameDirectories"].contains(key) {
                result[key] = try mergeItems(base: b as? [[String: Any]] ?? [], local: l as? [[String: Any]] ?? [], remote: r as? [[String: Any]] ?? [], path: field)
            } else { throw conflict(field) }
        }
        return result
    }
    private static func mergeItems(base: [[String: Any]], local: [[String: Any]], remote: [[String: Any]], path: String) throws -> [[String: Any]] {
        func index(_ items: [[String: Any]]) throws -> [String: Any] {
            var result: [String: Any] = [:]
            for item in items {
                guard let id = item["id"] as? String, result[id] == nil else { throw conflict(path) }
                result[id] = item
            }
            return result
        }
        let result = try mergeObject(base: index(base), local: index(local), remote: index(remote), path: path)
        var seen = Set<String>()
        return (remote + local).compactMap { item in
            guard let id = item["id"] as? String, seen.insert(id).inserted else { return nil }
            return result[id] as? [String: Any]
        }
    }
}
