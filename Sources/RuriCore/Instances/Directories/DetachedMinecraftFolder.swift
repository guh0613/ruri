import Foundation

/// Launcher preferences remain local when a Minecraft folder is unregistered.
/// Reattaching its marker restores the same instance IDs and on-disk history.
public struct DetachedMinecraftFolder: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID { directory.id }
    public var directory: GameDirectory
    public var instances: [GameInstance]
    public var selectedInstanceID: UUID?
    public let detachedAt: Date

    func validate(paths: LauncherPaths) throws {
        guard directory.isMinecraft,
              instances.allSatisfy({ $0.directoryID == id && $0.frozenMemory == nil }),
              Set(instances.map(\.id)).count == instances.count,
              selectedInstanceID == nil || instances.contains(where: { $0.id == selectedInstanceID }) else {
            throw RuriError.message("已移除的 Minecraft 文件夹记录无效。")
        }
        var snapshot = PersistentState()
        snapshot.gameDirectories = [directory]; snapshot.instances = instances
        for instance in instances {
            try instance.importedInstallation?.validate()
            if let icon = instance.iconPNG { try InstanceIconImage.validate(icon) }
        }
        try paths.configured(with: snapshot).validateDirectoryConfiguration()
    }
}
