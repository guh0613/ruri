import Foundation

public struct GameResourcePaths: Sendable {
    public let root: URL
    public let libraries: URL
    public let versions: URL
    public let assets: URL

    fileprivate init(root: URL, confined: Bool) throws {
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
        return try .init(root: root, confined: false)
    }
}
