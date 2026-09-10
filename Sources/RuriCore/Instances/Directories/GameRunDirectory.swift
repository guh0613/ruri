import Foundation

public enum GameRunDirectory: String, Codable, CaseIterable, Sendable, Identifiable {
    case isolated, shared, custom
    public var id: String { rawValue }
    public var title: String { switch self { case .isolated: "独立运行目录"; case .shared: "共享运行目录"; case .custom: "自定义运行目录" } }
    public var explanation: String {
        switch self {
        case .isolated: "此实例单独保存模组、存档和游戏设置。"
        case .shared: "与此实例文件夹中选择共享目录的其他实例共用模组、存档和游戏设置；一次只能运行一个。"
        case .custom: "在选定位置保存模组、存档和游戏设置；选用同一位置的 Ruri 实例一次只能运行一个。"
        }
    }
}

public enum GameIsolationPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case always, modded, never
    public var id: String { rawValue }
    public var title: String { switch self { case .always: "所有新实例独立"; case .modded: "有模组加载器的实例独立"; case .never: "新实例使用共享目录" } }
    public func directory(loader: LoaderKind) -> GameRunDirectory {
        switch self { case .always: .isolated; case .modded: loader == .vanilla ? .shared : .isolated; case .never: .shared }
    }
}

extension LauncherPaths {
    public func validateBinding(_ instance: GameInstance) throws {
        guard instanceRepositoryVersions?[instance.id] == instance.repositoryVersionID, runDirectory(for: instance.id) == (instance.runDirectory ?? .isolated),
              instance.directoryID == nil || instance.directoryID == directoryID(for: instance.id) else {
            throw RuriError.message("实例设置与本次操作的目录不一致，请刷新后重试。")
        }
        if runDirectory(for: instance.id) == .custom {
            guard let expected = instance.customRunDirectory, let actual = instanceCustomDirectories?[instance.id], expected.isSameLocation(as: actual) else { throw RuriError.message("自定义运行目录与本次操作的路径不一致，请刷新后重试。") }
        }
        try validateInstanceLocation(instance.id)
    }
    public func runDirectory(for instanceID: UUID) -> GameRunDirectory { instanceRunDirectories?[instanceID] ?? .isolated }
    /// Metadata that describes the game files must follow the run directory.
    /// Old isolated instances retain their existing metadata and backup paths.
    public func gameDataState(_ instanceID: UUID) -> URL {
        runDirectory(for: instanceID) == .isolated ? instance(instanceID) : game(instanceID).appendingPathComponent(".ruri")
    }
    public func including(_ instance: GameInstance) -> LauncherPaths {
        var versions = instanceRepositoryVersions ?? [:]
        versions[instance.id] = instance.repositoryVersionID
        var directoriesByInstance = instanceDirectories, modes = instanceRunDirectories ?? [:], custom = instanceCustomDirectories ?? [:]
        directoriesByInstance[instance.id] = instance.directoryID ?? directoryID(for: instance.id)
        modes[instance.id] = instance.runDirectory ?? .isolated
        custom[instance.id] = instance.runDirectory == .custom ? instance.customRunDirectory : nil
        var result = LauncherPaths(root: root, directories: directories, instanceDirectories: directoriesByInstance, newInstanceDirectoryID: newInstanceDirectoryID, instanceRunDirectories: modes, instanceCustomDirectories: custom, instanceRepositoryVersions: versions)
        result.repositoryImportID = repositoryImportID
        return result
    }
}
