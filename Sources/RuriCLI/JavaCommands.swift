import RuriLocalization
import Foundation
import RuriCore

extension CLI {
    static func manageJava(_ args: [String], paths: LauncherPaths) async throws {
        switch args.first {
        case "java":
            for entry in await JavaDiscovery.inventory(paths: paths) {
                print("\(entry.runtime?.label ?? Messages.CLIJavaCommands.manageJavaText1.localized) · \(entry.source)\n  \(entry.path)")
                if let id = entry.managedID { print(Messages.CLIJavaCommands.idText1(String(describing: id)).localized) }
                if let issue = entry.issue { print("  \(issue)") }
            }
        case "add-java":
            guard args.count == 2 else { throw RuriError.message(Messages.CLIJavaCommands.issueText1) }
            _ = try await JavaRuntimeStore.add(URL(fileURLWithPath: args[1]), paths: paths)
            print(Messages.CLIJavaCommands.issueText2.localized)
        case "forget-java":
            guard args.count == 2 else { throw RuriError.message(Messages.CLIJavaCommands.issueText3) }
            _ = try JavaRuntimeStore.forget(args[1], paths: paths); print(Messages.CLIJavaCommands.issueText4.localized)
        case "default-java":
            guard args.count == 2 else { throw RuriError.message(Messages.CLIJavaCommands.issueText5) }
            if args[1] == "automatic" { try StateStore.update(paths) { $0.settings.defaultJava = .automatic } }
            else {
                let file = try JavaDiscovery.executable(in: URL(fileURLWithPath: args[1]))
                _ = try await JavaRuntimeStore.add(file, paths: paths)
                _ = try JavaRuntimeStore.useByDefault(file.path, paths: paths)
            }
            print(Messages.CLIJavaCommands.fileText1.localized)
        case "repair-java":
            guard args.count == 2 else { throw RuriError.message(Messages.CLIJavaCommands.fileText2) }
            let installer = JavaInstaller(paths: paths)
            let runtime: RemoteJava
            if let stored = JavaRuntimeStore.descriptor(args[1], paths: paths) { runtime = stored }
            else if let available = try await installer.available().first(where: { $0.id == args[1] }) { runtime = available }
            else { throw RuriError.message(Messages.CLIJavaCommands.availableText1) }
            let result = try await installer.install(runtime, downloader: DownloadManager(), repairing: true) { p in
                if p.completed % 20 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
            }
            print(Messages.CLIJavaCommands.resultText1(String(describing: result.label)).localized)
        case "remove-java":
            guard args.count >= 2, Set(args.dropFirst(2)).isSubset(of: ["--apply", "--reset-references", "--partial"]) else {
                throw RuriError.message(Messages.CLIJavaCommands.resultText2)
            }
            let partial = args.contains("--partial")
            let references = try JavaRuntimeStore.references(to: args[1], paths: paths, partial: partial)
            print(references.isEmpty ? Messages.CLIJavaCommands.referencesText1.localized : Messages.CLIJavaCommands.javaReferences(LocalizedFormat.list(references)).localized)
            if args.contains("--apply") {
                _ = try JavaRuntimeStore.trash(args[1], paths: paths, resetReferences: args.contains("--reset-references"), partial: partial)
                print(Messages.CLIJavaCommands.referencesText3.localized)
            }
        default: break
        }
    }
}
