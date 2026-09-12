import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageContent(_ args: [String], paths: LauncherPaths) async throws {
        guard args.count >= 2, let id = UUID(uuidString: args[1]), try StateStore.load(paths).instances.contains(where: { $0.id == id }) else {
            throw RuriError.message(Messages.CLIContentCommands.instanceIDRequired)
        }
        let manager = ContentManager(paths: paths, instanceID: id)
        let kind: ContentKind
        if args.count > 2 {
            guard let selected = ContentKind(rawValue: args[2]) else { throw RuriError.message(Messages.CLIContentCommands.contentKind) }
            kind = selected
        } else { kind = .mod }
        if args[0] == "content" {
            guard args.count <= 3 else { throw RuriError.message(Messages.CLIContentCommands.contentUsage) }
            for file in try await manager.scan(kind) { print("\(file.enabled ? "[on]" : "[off]") \(file.title) \(file.version ?? "") — \(file.url.lastPathComponent)") }
            return
        }
        if args[0] == "update-content" {
            try await updateContent(args, paths: paths, id: id, kind: kind)
            return
        }
        guard args.count >= 5, ["enable", "disable", "remove"].contains(args[3]) else {
            throw RuriError.message(Messages.CLIContentCommands.contentActionUsage)
        }
        let apply = args.contains("--apply"), all = args.contains("--all")
        let names = Set(args.dropFirst(4).filter { $0 != "--apply" && $0 != "--all" })
        guard all ? names.isEmpty : !names.isEmpty else { throw RuriError.message(Messages.CLIContentCommands.filenamesRequired) }
        let lease = try apply ? GameRunLease.acquire(paths: paths, instanceID: id) : nil
        defer { withExtendedLifetime(lease) {} }
        let files = try await manager.scan(kind)
        let selected = all ? files : files.filter { names.contains($0.url.lastPathComponent) }
        guard all || Set(selected.map { $0.url.lastPathComponent }) == names else { throw RuriError.message(Messages.CLIContentCommands.selectionMismatch) }
        print(Messages.CLIContentCommands.selectedCount(String(describing: args[3]), Int64(selected.count), kind.title).localized)
        for file in selected { print(file.url.lastPathComponent) }
        if apply {
            switch args[3] {
            case "enable": try await manager.setEnabled(true, files: selected)
            case "disable": try await manager.setEnabled(false, files: selected)
            default:
                if let trashed = try await manager.remove(selected) { print(Messages.CLIContentCommands.movedToTrash(trashed.path).localized) }
            }
            print(Messages.CLIContentCommands.bulkOperationCompleted.localized)
        }
    }

    static func updateContent(_ args: [String], paths: LauncherPaths, id: UUID, kind: ContentKind) async throws {
        guard args.count >= 3 else { throw RuriError.message(Messages.CLIContentCommands.updateContentUsage) }
        var names = Set<String>(), manualFiles: [Int: URL] = [:], apply = false, all = false, index = 3
        while index < args.count {
            switch args[index] {
            case "--apply": apply = true
            case "--all": all = true
            case "--manual":
                guard index + 2 < args.count, let fileID = Int(args[index + 1]) else { throw RuriError.message(Messages.CLIContentCommands.manualFileRequired) }
                manualFiles[fileID] = URL(fileURLWithPath: args[index + 2]); index += 2
            default:
                guard !args[index].hasPrefix("--") else { throw RuriError.message(Messages.CLIContentCommands.unknownOption(String(describing: args[index]))) }
                names.insert(args[index])
            }
            index += 1
        }
        guard !all || names.isEmpty, !apply || all || !names.isEmpty else { throw RuriError.message(Messages.CLIContentCommands.filesRequiredForApply) }
        let lease = try apply ? GameRunLease.acquire(paths: paths, instanceID: id) : nil
        defer { withExtendedLifetime(lease) {} }
        guard let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CLIContentCommands.removedInstance) }
        let files = try await ContentManager(paths: paths, instanceID: id).scan(kind)
        let chosen = names.isEmpty ? files : files.filter { names.contains($0.url.lastPathComponent) }
        guard names.isEmpty || Set(chosen.map { $0.url.lastPathComponent }) == names else { throw RuriError.message(Messages.CLIContentCommands.partialContentSelection) }
        let records = chosen.compactMap(\.managed)
        let modrinth = ModrinthService(), hasCurse = records.contains { $0.provider == "curseforge" }
        let curseforge = CurseForgeService(apiKey: hasCurse ? try CurseForgeKeyStore.load() : "")
        let updates = try await modrinth.updates(for: records, instance: instance)
        let curseUpdates = hasCurse ? try await curseforge.updates(for: records, instance: instance) : []
        guard !updates.isEmpty || !curseUpdates.isEmpty else { print(Messages.CLIContentCommands.noCompatibleContentUpdates.localized); return }
        let updater = ContentBatchUpdater(modrinth: modrinth, curseforge: curseforge)
        let plan = try await updater.prepare(modrinth: updates, curseforge: curseUpdates, instance: instance, paths: paths)
        print(Messages.CLIContentCommands.contentUpdatePlan(Int64(plan.selectedIDs.count), Int64(plan.records.count)).localized)
        for record in plan.records {
            let previous = plan.baseline.first { $0.id == record.id }
            print("\(record.title)：\(previous?.versionName ?? Messages.CLIContentCommands.newlyAdded.localized) → \(record.versionName)\(previous?.enabled == false ? Messages.CLIContentCommands.keptDisabled.localized : "")")
        }
        for item in plan.curseforge where item.requiresManualDownload { print(Messages.CLIContentCommands.manualDownload(String(describing: item.id), item.pageURL.absoluteString).localized) }
        if apply {
            try await updater.install(plan, paths: paths, downloader: DownloadManager(), manualFiles: manualFiles) { p in print(p.stage) }
            print(Messages.CLIContentCommands.bulkUpdateCompleted.localized)
        }
    }
}
