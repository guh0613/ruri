import Foundation
import RuriCore

extension CLI {
    static func manageDirectories(_ args: [String], paths: LauncherPaths) throws {
        let state = try StateStore.load(paths)
        switch args.first ?? "list" {
        case "list":
            guard args.count <= 1 else { throw usage }
            print("\(state.selectedDirectoryID == nil || state.selectedDirectoryID == GameDirectory.defaultID ? "*" : " ") \(GameDirectory.defaultID) 默认实例文件夹\n  \(paths.root.path)")
            for directory in state.gameDirectories ?? [] {
                let count = state.instances.filter { $0.directoryID == directory.id }.count
                let availability = (try? directory.validateAvailability()) != nil ? "可用" : "无法访问"
                print("\(state.selectedDirectoryID == directory.id ? "*" : " ") \(directory.id) \(directory.name) [\(count) 个实例 · \(availability)]\n  \(directory.url.path)")
            }
            return
        case "add":
            guard args.count == 3 else { throw usage }
            let result = try MinecraftFolderStore.add(name: args[2], url: URL(fileURLWithPath: args[1]), paths: paths)
            print("Added \(result.selectedDirectoryID!.uuidString)"); return
        case "refresh":
            guard args.count == 1 else { throw usage }
            _ = try MinecraftFolderStore.refresh(state.selectedDirectoryID ?? GameDirectory.defaultID, paths: paths)
        case "select":
            guard args.count == 2, let id = UUID(uuidString: args[1]), id == GameDirectory.defaultID || state.gameDirectories?.contains(where: { $0.id == id }) == true else { throw usage }
            try GameDirectoryStore.select(id, paths: paths)
        case "rename", "relocate", "remove":
            guard args.count == (args[0] == "remove" ? 2 : 3), let id = UUID(uuidString: args[1]),
                  state.gameDirectories?.contains(where: { $0.id == id }) == true else { throw usage }
            if args[0] == "rename" { try GameDirectoryStore.rename(id, name: args[2], paths: paths) }
            else if args[0] == "relocate" { try GameDirectoryStore.relocate(id, to: URL(fileURLWithPath: args[2]), paths: paths) }
            else { try GameDirectoryStore.remove(id, paths: paths) }
        default: throw usage
        }
        print("Updated directory settings")
    }
    private static var usage: RuriError { .message("用法：ruri-cli directories [list | add <Minecraft-folder> <name> | select <uuid> | rename <uuid> <name> | relocate <uuid> <original-folder> | remove <uuid>]") }
}
