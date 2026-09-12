import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageModpackUpdate(_ args: [String], paths: LauncherPaths) async throws {
        guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else {
            throw RuriError.message(Messages.CLIModpackCommands.instanceText1)
        }
        let service = ModpackUpdater(paths: paths)
        if args[0] == "recover-pack-update" || args[0] == "rollback-pack" {
            guard args.count == 2 || (args.count == 3 && args[2] == "--apply") else { throw RuriError.message(Messages.CLIModpackCommands.serviceText1) }
            if args[0] == "recover-pack-update" {
                print(ModpackUpdateStore.hasPending(paths: paths, instanceID: id) ? Messages.CLIModpackCommands.serviceText2.localized : Messages.CLIModpackCommands.serviceText3.localized)
                if args.count == 3 { _ = try ModpackUpdateStore.recover(instanceID: id, paths: paths) }
            } else {
                print(ModpackUpdateStore.hasBackup(paths: paths, instanceID: id) ? Messages.CLIModpackCommands.serviceText4.localized : Messages.CLIModpackCommands.serviceText5.localized)
                if args.count == 3 {
                    let result = try await service.rollback(instance)
                    print(Messages.CLIModpackCommands.resultText1(Int64(result.preservedFiles)).localized)
                }
            }
            return
        }
        guard args.count >= 3, Set(args.dropFirst(3)).isSubset(of: ["--apply", "--replace-local"]) else { throw RuriError.message(Messages.CLIModpackCommands.resultText2) }
        let transfer = InstanceTransfer(paths: paths), downloader = DownloadManager()
        let prepared = try await transfer.prepare(URL(fileURLWithPath: args[2]))
        var plan: PreparedModpackUpdate?
        do {
            var content: [ContentInstallation] = []
            if !prepared.curseForgeFiles.isEmpty {
                let files = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).resolve(prepared.curseForgeFiles)
                content = try await CurseForgeService(apiKey: "").materialize(files, paths: paths, downloader: downloader, manualFiles: [:]) { _ in }
            }
            let preview = try await service.prepare(prepared, for: instance, content: content)
            plan = preview
            print("\(preview.current.name)：\(preview.current.version) → \(preview.incoming.version)")
            print(Messages.CLIModpackCommands.previewText1(String(describing: instance.gameVersion), String(describing: preview.incoming.settings.gameVersion), String(describing: preview.incoming.settings.loader.title)).localized)
            for item in preview.changes { print("[\(item.action.title)] \(item.id)\(item.explanation.map { " · " + $0 } ?? "")") }
            if args.contains("--apply") {
                let kept = args.contains("--replace-local") ? Set<String>() : Set(preview.changes.filter { $0.action == .keep }.map(\.id))
                _ = try await service.apply(preview, keepingLocal: kept) { p in
                    if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
                }
                print(Messages.CLIModpackCommands.keptText1.localized)
            }
            await service.discard(preview); await transfer.discard(prepared)
        } catch {
            if let plan { await service.discard(plan) }
            await transfer.discard(prepared); throw error
        }
    }
}
