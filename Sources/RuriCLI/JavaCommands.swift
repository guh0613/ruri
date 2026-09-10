import Foundation
import RuriCore

extension CLI {
    static func manageJava(_ args: [String], paths: LauncherPaths) async throws {
        switch args.first {
        case "java":
            for entry in await JavaDiscovery.inventory(paths: paths) {
                print("\(entry.runtime?.label ?? "不可用的 Java") · \(entry.source)\n  \(entry.path)")
                if let id = entry.managedID { print("  ID: \(id)") }
                if let issue = entry.issue { print("  \(issue)") }
            }
        case "add-java":
            guard args.count == 2 else { throw RuriError.message("用法：add-java <Java 路径或 JDK 文件夹>") }
            _ = try await JavaRuntimeStore.add(URL(fileURLWithPath: args[1]), paths: paths)
            print("Java 已添加")
        case "forget-java":
            guard args.count == 2 else { throw RuriError.message("用法：forget-java <手动添加的 java 可执行文件路径>") }
            _ = try JavaRuntimeStore.forget(args[1], paths: paths); print("已从手动列表移除，Java 文件和启动设置保留")
        case "default-java":
            guard args.count == 2 else { throw RuriError.message("用法：default-java <Java 路径或 automatic>") }
            if args[1] == "automatic" { try StateStore.update(paths) { $0.settings.defaultJava = .automatic } }
            else {
                let file = try JavaDiscovery.executable(in: URL(fileURLWithPath: args[1]))
                _ = try await JavaRuntimeStore.add(file, paths: paths)
                _ = try JavaRuntimeStore.useByDefault(file.path, paths: paths)
            }
            print("默认 Java 已更新")
        case "repair-java":
            guard args.count == 2 else { throw RuriError.message("用法：repair-java <运行时 ID，使用 java 命令查看>") }
            let installer = JavaInstaller(paths: paths)
            let runtime: RemoteJava
            if let stored = JavaRuntimeStore.descriptor(args[1], paths: paths) { runtime = stored }
            else if let available = try await installer.available().first(where: { $0.id == args[1] }) { runtime = available }
            else { throw RuriError.message("找不到此运行时的原始下载清单，请重新安装所需 Java 版本。") }
            let result = try await installer.install(runtime, downloader: DownloadManager(), repairing: true) { p in
                if p.completed % 20 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
            }
            print("已修复 \(result.label)")
        case "remove-java":
            guard args.count >= 2, Set(args.dropFirst(2)).isSubset(of: ["--apply", "--reset-references", "--partial"]) else {
                throw RuriError.message("用法：remove-java <运行时 ID> [--apply] [--reset-references] [--partial]")
            }
            let partial = args.contains("--partial")
            let references = try JavaRuntimeStore.references(to: args[1], paths: paths, partial: partial)
            print(references.isEmpty ? "没有启动设置引用此 Java" : "仍有以下设置引用：" + references.joined(separator: "、"))
            if args.contains("--apply") {
                _ = try JavaRuntimeStore.trash(args[1], paths: paths, resetReferences: args.contains("--reset-references"), partial: partial)
                print("Java 文件已移到废纸篓")
            }
        default: break
        }
    }
}
