import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageDirectories(_ args: [String], paths: LauncherPaths) throws {
        let state = try StateStore.load(paths)
        switch args.first ?? "list" {
        case "list":
            guard args.count <= 1 else { throw usage }
            print(Messages.CLIDirectories.stateText1(String(describing: state.selectedDirectoryID == nil || state.selectedDirectoryID == GameDirectory.defaultID ? "*" : " "), String(describing: GameDirectory.defaultID), String(describing: paths.root.path)).localized)
            for directory in state.gameDirectories ?? [] {
                let count = state.instances.filter { $0.directoryID == directory.id }.count
                let availability = (try? directory.validateAvailability()) != nil ? Messages.CLIDirectories.availabilityText1.localized : Messages.CLIDirectories.availabilityText2.localized
                print(Messages.CLIDirectories.availabilityText3(String(describing: state.selectedDirectoryID == directory.id ? "*" : " "), String(describing: directory.id), String(describing: directory.name), Int64(count), String(describing: availability), String(describing: directory.url.path)).localized)
            }
            for folder in state.detachedMinecraftFolders ?? [] {
                print(Messages.CLIDirectories.availabilityText4(String(describing: folder.id), String(describing: folder.directory.name), Int64(folder.instances.count), String(describing: folder.directory.url.path)).localized)
            }
            return
        case "add":
            guard args.count == 3 else { throw usage }
            let result = try MinecraftFolderStore.add(name: args[2], url: URL(fileURLWithPath: args[1]), paths: paths)
            print(Messages.CLIDirectories.resultText1(String(describing: result.selectedDirectoryID!.uuidString)).localized); return
        case "refresh":
            guard args.count == 1 else { throw usage }
            _ = try MinecraftFolderStore.refresh(state.selectedDirectoryID ?? GameDirectory.defaultID, paths: paths)
        case "imports":
            guard args.count == 1 else { throw usage }
            for item in try RepositoryImportStore.pending(directoryID: state.selectedDirectoryID ?? GameDirectory.defaultID, paths: paths) {
                print("\(item.id) \(item.name) · \(item.canFinish ? Messages.CLIDirectories.resultText2.localized : Messages.CLIDirectories.resultText3.localized)\n  \(item.workspace.path)")
            }
            return
        case "recover-import":
            guard args.count == 3, let id = UUID(uuidString: args[1]), ["--finish", "--keep-files"].contains(args[2]) else { throw usage }
            if let kept = try RepositoryImportStore.recover(id, directoryID: state.selectedDirectoryID ?? GameDirectory.defaultID, finish: args[2] == "--finish", paths: paths) {
                print(Messages.CLIDirectories.keptText1(String(describing: kept.path)).localized)
            } else { print(Messages.CLIDirectories.keptText2.localized) }
            return
        case "restore":
            guard (2...3).contains(args.count), let id = UUID(uuidString: args[1]),
                  let folder = state.detachedMinecraftFolders?.first(where: { $0.id == id }) else { throw usage }
            let url = args.count == 3 ? URL(fileURLWithPath: args[2]) : folder.directory.resolvingBookmark().url
            try MinecraftFolderStore.restore(id, from: url, paths: paths)
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
        print(Messages.CLIDirectories.idText1.localized)
    }
    private static var usage: RuriError { .message(Messages.CLIDirectories.usageText1.localized) }
}
