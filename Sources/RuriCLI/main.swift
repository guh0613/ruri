import Foundation
import RuriCore

@main struct CLI {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            let paths = LauncherPaths(root: root)
            let storedSource = (try? StateStore.load(paths).settings.downloadSource) ?? .automatic
            let source: DownloadSource
            if let requested = ProcessInfo.processInfo.environment["RURI_DOWNLOAD_SOURCE"] {
                guard let parsed = DownloadSource(rawValue: requested) else { throw RuriError.message("RURI_DOWNLOAD_SOURCE 应为 automatic、official 或 bmclapi") }
                source = parsed
            } else { source = storedSource }
            await NetworkRouting.shared.configure(source)
            switch args.first {
            case "java":
                for java in await JavaDiscovery.scan(paths: paths) { print("\(java.label)\n  \(java.path)") }
            case "install-java":
                guard args.count >= 2, let major = Int(args[1]) else { throw RuriError.message("用法：ruri-cli install-java <major> [aarch64|x86_64]") }
                let service = JavaInstaller(paths: paths)
                let architecture = args.count > 2 ? args[2] : JavaRuntime.hostArchitecture
                guard let runtime = try await service.available().first(where: { $0.major == major && $0.architecture == architecture }) else { throw RuriError.message("Mojang 没有提供所需运行时") }
                let installed = try await service.install(runtime, downloader: DownloadManager()) { p in
                    if p.completed % 20 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
                }
                print("Installed \(installed.label)\n\(installed.path)")
            case "fetch":
                guard args.count >= 5, let url = URL(string: args[1]), let size = Int64(args[4]), size >= 0,
                      args[3].range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil else { throw RuriError.message("用法：ruri-cli fetch <https-url> <output> <sha1> <bytes>") }
                let item = DownloadItem(url: url, destination: URL(fileURLWithPath: args[2]), sha1: args[3], size: size)
                let manager = DownloadManager()
                try await manager.fetch(item) { p in print("\(p.receivedBytes)/\(p.totalBytes ?? size) bytes; resumed \(p.resumedBytes)") }
                if let transfer = await manager.transfers().first { print("Source: \(transfer.host); attempts: \(transfer.attempt)") }
                print("Downloaded and verified \(item.destination.lastPathComponent)")
            case "versions":
                let catalog = try await GameInstaller(paths: paths).catalog()
                print("Latest release: \(catalog.latest.release)")
                for version in catalog.versions.prefix(20) { print("\(version.id) [\(version.type)]") }
            case "install":
                guard args.count >= 2 else { throw RuriError.message("用法：ruri-cli install <version> [fabric|quilt]") }
                guard let loader = args.count > 2 ? LoaderKind(rawValue: args[2]) : .vanilla else { throw RuriError.message("不支持的加载器名称") }
                var instance = GameInstance(name: "\(args[1]) \(loader.title)", gameVersion: args[1], loader: loader)
                instance = try await GameInstaller(paths: paths).install(instance) { progress in
                    if progress.completed % 100 == 0 || progress.completed == progress.total { print("\(progress.stage) \(progress.completed)/\(progress.total)") }
                }
                var state = try StateStore.load(paths); state.instances.append(instance); state.selectedInstanceID = instance.id
                try StateStore.save(state, to: paths)
                print("Installed \(instance.id)")
            case "export-instance":
                guard args.count >= 3, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli export-instance <instance-uuid> <output.zip> [ruri|multimc|mcbbs|mrpack]") }
                guard let format = args.count > 3 ? InstanceExportFormat(rawValue: args[3]) : .ruri else { throw RuriError.message("导出格式为 ruri、multimc、mcbbs 或 mrpack") }
                try await InstanceTransfer(paths: paths).export(instance, to: URL(fileURLWithPath: args[2]), format: format) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                print("Exported \(instance.name)")
            case "import-instance":
                guard args.count >= 2 else { throw RuriError.message("用法：ruri-cli import-instance <folder-or-zip> [name]") }
                let transfer = InstanceTransfer(paths: paths)
                let prepared = try await transfer.prepare(URL(fileURLWithPath: args[1]))
                print("\(prepared.format): \(prepared.instance.subtitle), \(prepared.fileCount) files")
                for warning in prepared.warnings { print(warning) }
                do {
                    let imported = try await transfer.install(prepared, name: args.count > 2 ? args[2] : prepared.instance.name, importJVMArguments: prepared.format == "MCBBS", installer: GameInstaller(paths: paths)) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                    var state = try StateStore.load(paths); state.instances.append(imported); state.selectedInstanceID = imported.id
                    try StateStore.save(state, to: paths); await transfer.discard(prepared)
                    print("Imported \(imported.id)")
                } catch { await transfer.discard(prepared); throw error }
            case "repair":
                guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli repair <instance-uuid>") }
                try await GameInstaller(paths: paths).repair(instance) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                print("Repaired \(instance.id)")
            case "plan":
                let state = try StateStore.load(paths)
                guard let instance = state.instances.last else { throw RuriError.message("没有已安装实例") }
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let runtimes = await JavaDiscovery.scan(paths: paths)
                let java = try JavaDiscovery.select(from: runtimes, major: instance.preferredJavaMajor(default: manifest.requiredJava), architecture: GameInstaller.architecture(for: manifest))
                let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "RuriTest"), paths: paths)
                print(plan.redactedCommand)
            case "install-content":
                guard args.count >= 3, let id = UUID(uuidString: args[2]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli install-content <project> <instance-uuid> [version-id]") }
                let service = ModrinthService()
                let versions = try await service.versions(project: args[1], game: instance.gameVersion, loader: instance.loader.rawValue)
                guard let version = args.count > 3 ? versions.first(where: { $0.id == args[3] }) : versions.first else { throw RuriError.message("找不到兼容内容版本") }
                try await service.install(version: version, type: "mod", instance: instance, paths: paths, downloader: DownloadManager()) { p in print("\(p.stage) \(p.completed)/\(p.total)") }
                print("Installed \(version.version_number)")
            case "content":
                guard args.count >= 2, let id = UUID(uuidString: args[1]) else { throw RuriError.message("用法：ruri-cli content <instance-uuid>") }
                for file in try await ContentManager(paths: paths, instanceID: id).scan(.mod) { print("\(file.enabled ? "[on]" : "[off]") \(file.title) \(file.version ?? "") — \(file.filename)") }
            case "launch":
                let state = try StateStore.load(paths)
                let requestedID = args.count > 1 ? UUID(uuidString: args[1]) : state.selectedInstanceID
                if args.count > 1 && requestedID == nil { throw RuriError.message("无效的实例 UUID") }
                let selected = requestedID.flatMap { id in state.instances.first { $0.id == id } } ?? (args.count > 1 ? nil : state.instances.last)
                guard let instance = selected, let account = state.accounts.first(where: { $0.id == state.activeAccountID }) else { throw RuriError.message("请先安装实例并添加账号") }
                guard account.kind == .offline else { throw RuriError.message("命令行启动当前仅支持离线账号；Microsoft 账号请在应用中启动。") }
                try await ContentManager(paths: paths, instanceID: instance.id).recover()
                try await WorldManager(paths: paths, instanceID: instance.id).recover()
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let java = try JavaDiscovery.select(from: await JavaDiscovery.scan(paths: paths), major: instance.preferredJavaMajor(default: manifest.requiredJava), architecture: GameInstaller.architecture(for: manifest))
                let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths)
                let game = GameProcess()
                let status = await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                    do {
                        try game.start(plan: plan) { line in
                            try? FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8))
                        } onExit: { code in continuation.resume(returning: code) }
                    } catch { print(error.localizedDescription); continuation.resume(returning: -1) }
                }
                print("Game exit: \(status)")
                if status != 0 { exit(status) }
            default: print("Ruri CLI\n  java\n  versions\n  install <version> [fabric|quilt|forge|neoforge]\n  install-java <major> [aarch64|x86_64]\n  repair <instance-uuid>\n  install-content <project> <instance-uuid> [version-id]\n  content <instance-uuid>\n  plan\n  launch [instance-uuid] (offline account)\n\nRURI_DATA_DIR overrides the data directory.")
            }
        } catch { fputs("Error: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
