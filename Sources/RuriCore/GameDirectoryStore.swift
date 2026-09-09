import Foundation

public enum GameDirectoryStore {
    @discardableResult public static func add(name: String, url: URL, paths: LauncherPaths) throws -> PersistentState {
        var created: GameDirectory?
        let hadMarker = FileManager.default.fileExists(atPath: url.appendingPathComponent(GameDirectory.markerName).path)
        do {
            return try StateStore.update(paths) { state in
                let directory = try GameDirectory.create(name: name, at: url, paths: paths.configured(with: state))
                created = directory
                state.gameDirectories = (state.gameDirectories ?? []) + [directory]
                state.selectedDirectoryID = directory.id
            }
        } catch {
            // Roll back only the marker we just created, only while the folder
            // is still empty. Never delete the selected folder or user content.
            if !hadMarker, let created, (try? created.validateAvailability()) != nil,
               let entries = try? FileManager.default.contentsOfDirectory(at: created.url, includingPropertiesForKeys: nil),
               entries.allSatisfy({ [GameDirectory.markerName, ".DS_Store"].contains($0.lastPathComponent) }) {
                try? FileManager.default.removeItem(at: created.url.appendingPathComponent(GameDirectory.markerName))
            }
            throw error
        }
    }
    @discardableResult public static func select(_ id: UUID, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { state in
            guard id == GameDirectory.defaultID || state.gameDirectories?.contains(where: { $0.id == id }) == true else { throw RuriError.message("此实例文件夹已被取消登记。") }
            state.selectedDirectoryID = id
        }
    }
    @discardableResult public static func rename(_ id: UUID, name: String, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { state in
            guard let index = state.gameDirectories?.firstIndex(where: { $0.id == id }) else { throw RuriError.message("找不到实例文件夹。") }
            state.gameDirectories?[index].name = try GameDirectory.validName(name)
        }
    }
    @discardableResult public static func relocate(_ id: UUID, to url: URL, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { state in
            guard let index = state.gameDirectories?.firstIndex(where: { $0.id == id }), let original = state.gameDirectories?[index] else { throw RuriError.message("找不到实例文件夹。") }
            let current = paths.configured(with: state)
            state.gameDirectories?[index] = try original.relocated(to: url, paths: current)
            let relocated = paths.configured(with: state)
            for instance in state.instances where instance.directoryID == id {
                guard !GameRunLease.isHeld(paths: relocated, instanceID: instance.id),
                      try !GameSessionStore.list(paths: relocated, instanceID: instance.id).contains(where: { !$0.state.isFinished && GameMonitorClient.activity($0) != .inactive }) else {
                    throw RuriError.message("此文件夹仍有游戏运行或会话状态待确认，请先在游戏中退出并检查运行记录。")
                }
            }
        }
    }
    @discardableResult public static func remove(_ id: UUID, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { state in
            guard !state.instances.contains(where: { $0.directoryID == id }) else { throw RuriError.message("文件夹仍有实例，不能取消登记。") }
            guard let directory = state.gameDirectories?.first(where: { $0.id == id }) else { throw RuriError.message("找不到实例文件夹。") }
            if (try? directory.validateAvailability()) != nil {
                let instances = directory.url.appendingPathComponent("instances")
                if FileManager.default.fileExists(atPath: instances.path) {
                    guard try FileManager.default.contentsOfDirectory(atPath: instances.path).allSatisfy({ $0 == ".DS_Store" }) else { throw RuriError.message("文件夹中仍有未登记或正在安装的实例，请先处理这些实例再取消登记。") }
                }
            }
            // Empty markers can be kept and reattached later. No file deletion.
            state.gameDirectories?.removeAll { $0.id == directory.id }
            if state.selectedDirectoryID == id { state.selectedDirectoryID = nil }
        }
    }
}
