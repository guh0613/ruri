import Foundation
import RuriCore

@main struct CLI {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            let paths = LauncherPaths(root: root)
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
            case "versions":
                let catalog = try await GameInstaller(paths: paths).catalog()
                print("Latest release: \(catalog.latest.release)")
                for version in catalog.versions.prefix(20) { print("\(version.id) [\(version.type)]") }
            case "install":
                guard args.count >= 2 else { throw RuriError.message("用法：ruri-cli install <version> [fabric|quilt]") }
                let loader = args.count > 2 ? LoaderKind(rawValue: args[2]) ?? .vanilla : .vanilla
                var instance = GameInstance(name: "\(args[1]) \(loader.title)", gameVersion: args[1], loader: loader)
                instance = try await GameInstaller(paths: paths).install(instance) { progress in
                    if progress.completed % 100 == 0 || progress.completed == progress.total { print("\(progress.stage) \(progress.completed)/\(progress.total)") }
                }
                var state = try StateStore.load(paths); state.instances.append(instance); state.selectedInstanceID = instance.id
                try StateStore.save(state, to: paths)
                print("Installed \(instance.id)")
            case "plan":
                let state = try StateStore.load(paths)
                guard let instance = state.instances.last else { throw RuriError.message("没有已安装实例") }
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let runtimes = await JavaDiscovery.scan(paths: paths)
                let java = try JavaDiscovery.select(from: runtimes, major: manifest.requiredJava, architecture: GameInstaller.architecture(for: manifest))
                let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "RuriTest"), paths: paths)
                print(plan.redactedCommand)
            case "launch":
                let state = try StateStore.load(paths)
                guard let instance = state.instances.last, let account = state.accounts.first(where: { $0.id == state.activeAccountID }) else { throw RuriError.message("请先安装实例并添加账号") }
                guard account.kind == .offline else { throw RuriError.message("命令行启动当前仅支持离线账号；Microsoft 账号请在应用中启动。") }
                try await ContentManager(paths: paths, instanceID: instance.id).recover()
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let java = try JavaDiscovery.select(from: await JavaDiscovery.scan(paths: paths), major: manifest.requiredJava, architecture: GameInstaller.architecture(for: manifest))
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
            default: print("Ruri CLI\n  java\n  versions\n  install <version> [fabric|quilt]\n  install-java <major> [aarch64|x86_64]\n  plan\n  launch (offline account)\n\nRURI_DATA_DIR overrides the data directory.")
            }
        } catch { fputs("Error: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
