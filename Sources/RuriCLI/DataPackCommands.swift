import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageDataPacks(_ args: [String], paths: LauncherPaths) async throws {
        let usage = Messages.CLIDataPackCommands.usageText1.localized
        guard args.count >= 3, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message(usage) }
        let manager = WorldManager(paths: paths, instanceID: id), folder = args[2]
        if args.count == 3 {
            for pack in try await manager.dataPacks(folder: folder) {
                print("\(pack.enabled ? "[on]" : "[off]") \(pack.id) — \(pack.error ?? pack.description)")
            }
            return
        }
        if args[3] == "order" {
            let apply = args.last == "--apply"
            let lease = try apply ? GameRunLease.acquire(paths: paths, instanceID: id) : nil
            defer { withExtendedLifetime(lease) {} }
            let current = try await manager.dataPackPriority(folder: folder)
            let keys = Array(args.dropFirst(4).filter { $0 != "--apply" })
            print(Messages.CLIDataPackCommands.keysText1.localized)
            for key in keys.isEmpty ? current.keys : keys { print(key) }
            if apply { try await manager.setDataPackPriority(keys, folder: folder, expecting: current) }
            return
        }
        if args[3] == "search" {
            guard args.count == 5 else { throw RuriError.message(usage) }
            let results = try await WorldDataPackDownloads().search(args[4], game: instance.gameVersion)
            for project in results.hits { print("\(project.id)  \(project.slug) — \(project.title)") }
            print(Messages.CLIDataPackCommands.resultsText1(Int64(results.total_hits)).localized)
            return
        }
        if args[3] == "download" {
            let arguments = args.filter { $0 != "--apply" }, apply = args.last == "--apply"
            guard (5...6).contains(arguments.count), !args.contains("--apply") || apply else { throw RuriError.message(usage) }
            let service = WorldDataPackDownloads(), versions = try await service.versions(project: arguments[4], game: instance.gameVersion)
            let selected = arguments.count == 6 ? versions.first(where: { $0.id == arguments[5] }) : versions.first(where: { $0.version_type == nil || $0.version_type == "release" })
            guard let selected else { throw RuriError.message(Messages.CLIDataPackCommands.selectedText1) }
            let plan = try await service.prepare(selected, game: instance.gameVersion)
            for version in plan.versions { print("\(version.id)  \(version.name) — \(version.version_number)") }
            print(Messages.CLIDataPackCommands.planText1(Int64(plan.files.count), String(describing: plan.downloadSize)).localized)
            if apply {
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                try await service.install(plan, instance: instance, folder: folder, paths: paths, downloader: DownloadManager()) { p in print(p.stage) }
                print(Messages.CLIDataPackCommands.leaseText1.localized)
            }
            return
        }
        guard (5...6).contains(args.count), ["import", "enable", "disable", "remove"].contains(args[3]), args.count == 5 || args[5] == "--apply" else { throw RuriError.message(usage) }
        print("\(args[3])：\(folder)/\(args[4])")
        guard args.count == 6 else { print(Messages.CLIDataPackCommands.leaseText2.localized); return }
        let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
        defer { withExtendedLifetime(lease) {} }
        switch args[3] {
        case "import": try await manager.importDataPack(from: URL(fileURLWithPath: args[4]), folder: folder)
        case "enable", "disable": try await manager.setDataPackEnabled(args[3] == "enable", name: args[4], folder: folder)
        default:
            if let trash = try await manager.removeDataPack(name: args[4], folder: folder) { print(Messages.CLIDataPackCommands.trashText1(String(describing: trash.path)).localized) }
        }
        print(Messages.CLIDataPackCommands.trashText2(String(describing: try await manager.dataPackBackup(folder: folder).path)).localized)
    }
}
