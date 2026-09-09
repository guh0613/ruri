import Foundation
import RuriCore

extension CLI {
    static func manageDirectories(_ args: [String], paths: LauncherPaths) throws {
        var state = try StateStore.load(paths)
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
            let directory = try GameDirectory.create(name: args[2], at: URL(fileURLWithPath: args[1]), paths: paths)
            state.gameDirectories = (state.gameDirectories ?? []) + [directory]
            state.selectedDirectoryID = directory.id
            try StateStore.save(state, to: paths)
            print("Added \(directory.id) \(directory.name)"); return
        case "select":
            guard args.count == 2, let id = UUID(uuidString: args[1]), id == GameDirectory.defaultID || state.gameDirectories?.contains(where: { $0.id == id }) == true else { throw usage }
            state.selectedDirectoryID = id
        case "rename", "relocate", "remove":
            guard args.count == (args[0] == "remove" ? 2 : 3), let id = UUID(uuidString: args[1]),
                  let index = state.gameDirectories?.firstIndex(where: { $0.id == id }) else { throw usage }
            if args[0] == "rename" { state.gameDirectories?[index].name = try GameDirectory.validName(args[2]) }
            else if args[0] == "relocate", let original = state.gameDirectories?[index] {
                state.gameDirectories?[index] = try original.relocated(to: URL(fileURLWithPath: args[2]), paths: paths)
                let relocatedPaths = paths.configured(with: state)
                let ids = state.instances.filter { $0.directoryID == id }.map(\.id)
                for instanceID in ids {
                    guard !GameRunLease.isHeld(paths: relocatedPaths, instanceID: instanceID),
                          try !GameSessionStore.list(paths: relocatedPaths, instanceID: instanceID).contains(where: { !$0.state.isFinished && GameMonitorClient.activity($0) != .inactive }) else { throw RuriError.message("请先结束此文件夹中的游戏并确认运行记录，再重新定位。") }
                }
            } else {
                guard !state.instances.contains(where: { $0.directoryID == id }) else { throw RuriError.message("文件夹仍有实例，不能取消登记。此操作不会删除磁盘上的文件。") }
                state.gameDirectories?.remove(at: index)
                if state.selectedDirectoryID == id { state.selectedDirectoryID = nil }
            }
        default: throw usage
        }
        try StateStore.save(state, to: paths)
        print("Updated directory settings")
    }
    private static var usage: RuriError { .message("用法：ruri-cli directories [list | add <empty-folder> <name> | select <uuid> | rename <uuid> <name> | relocate <uuid> <original-folder> | remove <uuid>]") }
}
