import Foundation
import RuriCore

extension CLI {
    static func manageDataPacks(_ args: [String], paths: LauncherPaths) async throws {
        let usage = "用法：datapacks <instance-uuid> <世界文件夹> [import <路径> | enable|disable|remove <文件名>] [--apply]"
        guard args.count >= 3, let id = UUID(uuidString: args[1]), try StateStore.load(paths).instances.contains(where: { $0.id == id }) else { throw RuriError.message(usage) }
        let manager = WorldManager(paths: paths, instanceID: id), folder = args[2]
        if args.count == 3 {
            for pack in try await manager.dataPacks(folder: folder) {
                print("\(pack.enabled ? "[on]" : "[off]") \(pack.id) — \(pack.error ?? pack.description)")
            }
            return
        }
        guard (5...6).contains(args.count), ["import", "enable", "disable", "remove"].contains(args[3]), args.count == 5 || args[5] == "--apply" else { throw RuriError.message(usage) }
        print("\(args[3])：\(folder)/\(args[4])")
        guard args.count == 6 else { print("添加 --apply 执行。数据包更改将在下次进入世界时生效。"); return }
        let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
        defer { withExtendedLifetime(lease) {} }
        switch args[3] {
        case "import": try await manager.importDataPack(from: URL(fileURLWithPath: args[4]), folder: folder)
        case "enable", "disable": try await manager.setDataPackEnabled(args[3] == "enable", name: args[4], folder: folder)
        default:
            if let trash = try await manager.removeDataPack(name: args[4], folder: folder) { print("已移到废纸篓：\(trash.path)") }
        }
        print("配置备份：\(try await manager.dataPackBackup(folder: folder).path)")
    }
}
