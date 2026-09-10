import Foundation

public struct GameResourcePaths: Sendable {
    public let root: URL
    public let libraries: URL
    public let versions: URL
    public let assets: URL

    init(root: URL, confined: Bool) throws {
        self.root = root
        func directory(_ name: String) throws -> URL {
            // An imported installation owns its files. Its resource folders
            // must not redirect repair into another instance or shared cache.
            try confined ? LauncherPaths.safePath(name, within: root) : root.appendingPathComponent(name)
        }
        libraries = try directory("libraries")
        versions = try directory("versions")
        assets = try directory("assets")
    }
}

extension LauncherPaths {
    public func resources(for instance: GameInstance) throws -> GameResourcePaths {
        if let imported = instance.importedInstallation {
            try imported.validate()
            return try .init(root: Self.safePath("installation", within: self.instance(instance.id)), confined: true)
        }
        return try .init(root: instance.repositoryVersionID == nil ? root : directoryRoot(directoryID(for: instance.id)), confined: false)
    }
}

extension GameResourcePaths {
    func libraryFile(_ artifact: Artifact, fallback: String? = nil) throws -> URL {
        if let relative = artifact.repositoryPath { return try LauncherPaths.safePath(relative, within: root) }
        guard let path = artifact.path ?? fallback else { throw RuriError.message("依赖库缺少文件路径。") }
        return try LauncherPaths.safePath(path, within: libraries)
    }
}
