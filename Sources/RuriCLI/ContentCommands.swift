import Foundation
import RuriCore

extension CLI {
    static func manageContent(_ args: [String], paths: LauncherPaths) async throws {
        guard args.count >= 2, let id = UUID(uuidString: args[1]), try StateStore.load(paths).instances.contains(where: { $0.id == id }) else {
            throw RuriError.message("请指定已有实例的 UUID。")
        }
        let manager = ContentManager(paths: paths, instanceID: id)
        let kind: ContentKind
        if args.count > 2 {
            guard let selected = ContentKind(rawValue: args[2]) else { throw RuriError.message("内容类型为 mod、resourcepack 或 shader。") }
            kind = selected
        } else { kind = .mod }
        if args[0] == "content" {
            guard args.count <= 3 else { throw RuriError.message("用法：content <instance-uuid> [mod|resourcepack|shader]") }
            for file in try await manager.scan(kind) { print("\(file.enabled ? "[on]" : "[off]") \(file.title) \(file.version ?? "") — \(file.url.lastPathComponent)") }
            return
        }
        guard args.count >= 5, ["enable", "disable", "remove"].contains(args[3]) else {
            throw RuriError.message("用法：content-action <instance-uuid> <kind> <enable|disable|remove> <filename ... | --all> [--apply]")
        }
        let apply = args.contains("--apply"), all = args.contains("--all")
        let names = Set(args.dropFirst(4).filter { $0 != "--apply" && $0 != "--all" })
        guard all ? names.isEmpty : !names.isEmpty else { throw RuriError.message("请选择具体文件名，或仅使用 --all。") }
        let lease = try apply ? GameRunLease.acquire(paths: paths, instanceID: id) : nil
        defer { withExtendedLifetime(lease) {} }
        let files = try await manager.scan(kind)
        let selected = all ? files : files.filter { names.contains($0.url.lastPathComponent) }
        guard all || Set(selected.map { $0.url.lastPathComponent }) == names else { throw RuriError.message("部分文件不在当前列表中。请用 content 命令查看准确文件名，停用文件包含 .disabled 后缀。") }
        print("\(args[3])：\(selected.count) 项\(kind.title)")
        for file in selected { print(file.url.lastPathComponent) }
        if apply {
            switch args[3] {
            case "enable": try await manager.setEnabled(true, files: selected)
            case "disable": try await manager.setEnabled(false, files: selected)
            default:
                if let trashed = try await manager.remove(selected) { print("已移到废纸篓：\(trashed.path)") }
            }
            print("批量操作已完成")
        }
    }
}
