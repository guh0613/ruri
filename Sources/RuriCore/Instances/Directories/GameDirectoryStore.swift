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
        var leases: [GameRunLease] = []
        var sharedLease: SharedGameDirectoryLease?
        defer { withExtendedLifetime(leases) {}; withExtendedLifetime(sharedLease) {} }
        return try StateStore.update(paths) { state in
            guard let index = state.gameDirectories?.firstIndex(where: { $0.id == id }), let original = state.gameDirectories?[index] else { throw RuriError.message("找不到实例文件夹。") }
            try InstanceCopyGuard.requireDirectoryAvailable(id, paths: paths)
            try InstanceMoveGuard.requireDirectoryAvailable(id, paths: paths)
            let current = paths.configured(with: state)
            state.gameDirectories?[index] = try original.relocated(to: url, paths: current)
            if original.url.standardizedFileURL.resolvingSymlinksInPath().path != url.standardizedFileURL.resolvingSymlinksInPath().path,
               (try? original.validateAvailability()) != nil { throw RuriError.message("原实例文件夹仍可访问，请先完成移动，或通过导入处理另一份副本。") }
            let relocated = paths.configured(with: state)
            for instance in state.instances where instance.directoryID == id {
                // Only the managed history/metadata moved. A custom game root
                // may independently be offline and must not prevent finding it.
                var metadata = instance; metadata.runDirectory = .isolated
                leases.append(try GameRunLease.acquire(paths: relocated.including(metadata), instanceID: instance.id))
            }
            if let shared = state.instances.first(where: { $0.directoryID == id && $0.runDirectory == .shared }) {
                sharedLease = try SharedGameDirectoryLease.acquire(paths: relocated, instanceID: shared.id, ignoringSession: nil)
            }
        }
    }
    public static func resolveBookmarks(paths: LauncherPaths) throws -> PersistentState {
        let initial = try StateStore.load(paths)
        for directory in initial.gameDirectories ?? [] where (try? directory.validateAvailability()) == nil {
            let candidate = directory.resolvingBookmark()
            guard candidate.url.standardizedFileURL.path != directory.url.standardizedFileURL.path else { continue }
            // Busy or uncertain locations stay at their recorded paths. The
            // normal availability UI can explain how to reconnect them.
            _ = try? relocate(directory.id, to: candidate.url, paths: paths)
        }
        return try StateStore.load(paths)
    }
    @discardableResult public static func remove(_ id: UUID, paths: LauncherPaths) throws -> PersistentState {
        try StateStore.update(paths) { state in
            try InstanceMoveGuard.requireDirectoryAvailable(id, paths: paths)
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
