import Foundation
import RuriCore

@main struct CLI {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            let paths = LauncherPaths(root: root)
            switch args.first {
            case "java":
                for java in await JavaDiscovery.scan(paths: paths) { print("\(java.label)\n  \(java.path)") }
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
            default: print("Ruri CLI\n  java\n  versions\n  install <version> [fabric|quilt]\n  plan\n\nRURI_DATA_DIR overrides the data directory.")
            }
        } catch { fputs("Error: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
