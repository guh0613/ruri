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
        if args[0] == "update-content" {
            try await updateContent(args, paths: paths, id: id, kind: kind)
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

    static func updateContent(_ args: [String], paths: LauncherPaths, id: UUID, kind: ContentKind) async throws {
        guard args.count >= 3 else { throw RuriError.message("用法：update-content <instance-uuid> <kind> [filename ... | --all] [--apply] [--manual <file-id> <path>]") }
        var names = Set<String>(), manualFiles: [Int: URL] = [:], apply = false, all = false, index = 3
        while index < args.count {
            switch args[index] {
            case "--apply": apply = true
            case "--all": all = true
            case "--manual":
                guard index + 2 < args.count, let fileID = Int(args[index + 1]) else { throw RuriError.message("--manual 后需要 CurseForge 文件 ID 和本地路径。") }
                manualFiles[fileID] = URL(fileURLWithPath: args[index + 2]); index += 2
            default:
                guard !args[index].hasPrefix("--") else { throw RuriError.message("无法识别的选项：\(args[index])") }
                names.insert(args[index])
            }
            index += 1
        }
        guard !all || names.isEmpty, !apply || all || !names.isEmpty else { throw RuriError.message("应用更新时请选择具体文件名，或使用 --all。") }
        let lease = try apply ? GameRunLease.acquire(paths: paths, instanceID: id) : nil
        defer { withExtendedLifetime(lease) {} }
        guard let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("实例已移除。") }
        let files = try await ContentManager(paths: paths, instanceID: id).scan(kind)
        let chosen = names.isEmpty ? files : files.filter { names.contains($0.url.lastPathComponent) }
        guard names.isEmpty || Set(chosen.map { $0.url.lastPathComponent }) == names else { throw RuriError.message("部分文件不在当前内容列表中。") }
        let records = chosen.compactMap(\.managed)
        let modrinth = ModrinthService(), hasCurse = records.contains { $0.provider == "curseforge" }
        let curseforge = CurseForgeService(apiKey: hasCurse ? try CurseForgeKeyStore.load() : "")
        let updates = try await modrinth.updates(for: records, instance: instance)
        let curseUpdates = hasCurse ? try await curseforge.updates(for: records, instance: instance) : []
        guard !updates.isEmpty || !curseUpdates.isEmpty else { print("没有可用的兼容正式版更新。"); return }
        let updater = ContentBatchUpdater(modrinth: modrinth, curseforge: curseforge)
        let plan = try await updater.prepare(modrinth: updates, curseforge: curseUpdates, instance: instance, paths: paths)
        print("更新 \(plan.selectedIDs.count) 项内容，含依赖共 \(plan.records.count) 个文件")
        for record in plan.records {
            let previous = plan.baseline.first { $0.id == record.id }
            print("\(record.title)：\(previous?.versionName ?? "新增") → \(record.versionName)\(previous?.enabled == false ? "（保持停用）" : "")")
        }
        for item in plan.curseforge where item.requiresManualDownload { print("手动下载 \(item.id)：\(item.pageURL.absoluteString)") }
        if apply {
            try await updater.install(plan, paths: paths, downloader: DownloadManager(), manualFiles: manualFiles) { p in print(p.stage) }
            print("批量更新完成")
        }
    }
}
