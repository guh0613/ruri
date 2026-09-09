import Foundation
import RuriCore

@main struct CLI {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            let basePaths = LauncherPaths(root: root)
            let paths = try basePaths.configured(with: StateStore.load(basePaths))
            let storedSource = (try? StateStore.load(paths).settings.downloadSource) ?? .automatic
            let source: DownloadSource
            if let requested = ProcessInfo.processInfo.environment["RURI_DOWNLOAD_SOURCE"] {
                guard let parsed = DownloadSource(rawValue: requested) else { throw RuriError.message("RURI_DOWNLOAD_SOURCE 应为 automatic、official 或 bmclapi") }
                source = parsed
            } else { source = storedSource }
            await NetworkRouting.shared.configure(source)
            switch args.first {
            case "directories":
                try manageDirectories(Array(args.dropFirst()), paths: paths)
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
                try StateStore.update(paths) { state in state.instances.append(instance); state.selectedInstanceID = instance.id }
                print("Installed \(instance.id)")
            case "export-instance":
                guard args.count >= 3, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli export-instance <instance-uuid> <output.zip> [ruri|multimc|mcbbs|mrpack]") }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
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
                    try StateStore.update(paths) { state in state.instances.append(imported); state.selectedInstanceID = imported.id }
                    await transfer.discard(prepared)
                    print("Imported \(imported.id)")
                } catch { await transfer.discard(prepared); throw error }
            case "repair":
                guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli repair <instance-uuid>") }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
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
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
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
                let launchArgs = args.dropFirst().filter { $0 != "--detach" }
                guard launchArgs.count <= 1 else { throw RuriError.message("用法：ruri-cli launch [instance-uuid] [--detach]") }
                let requestedID = launchArgs.first.flatMap(UUID.init(uuidString:)) ?? (launchArgs.isEmpty ? state.selectedInstanceID : nil)
                if !launchArgs.isEmpty && requestedID == nil { throw RuriError.message("无效的实例 UUID") }
                let selected = requestedID.flatMap { id in state.instances.first { $0.id == id } } ?? (launchArgs.isEmpty ? state.instances.last : nil)
                guard let instance = selected, let account = state.accounts.first(where: { $0.id == state.activeAccountID }) else { throw RuriError.message("请先安装实例并添加账号") }
                guard account.kind == .offline else { throw RuriError.message("命令行启动当前仅支持离线账号；Microsoft 账号请在应用中启动。") }
                let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: account.kind.rawValue)
                var handedOff = false
                do {
                    try recorder.transition(.recovery)
                    try await ContentManager(paths: paths, instanceID: instance.id).recover()
                    try await WorldManager(paths: paths, instanceID: instance.id).recover()
                    try recorder.transition(.manifest)
                    let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                    try recorder.transition(.java)
                    let java = try JavaDiscovery.select(from: await JavaDiscovery.scan(paths: paths), major: instance.preferredJavaMajor(default: manifest.requiredJava), architecture: GameInstaller.architecture(for: manifest))
                    try recorder.setJava(java.label + " · " + java.version)
                    try recorder.transition(.arguments)
                    let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths)
                    try recorder.append("[Ruri] \(plan.redactedCommand)")
                    try recorder.transition(.starting)
                    try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [])
                    handedOff = true
                    print("Game session: \(recorder.record.id)")
                    if args.contains("--detach") { print("游戏已交由后台监控，退出命令行不会结束游戏。"); break }
                    let cursor = try GameSessionLogCursor(paths: paths, session: recorder.record)
                    while true {
                        let record = try GameSessionStore.load(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
                        let activity = GameMonitorClient.activity(record)
                        let final = activity == .inactive
                        var changed: Bool
                        repeat {
                            changed = try await cursor.refresh(final: final)
                            for line in await cursor.updates { try? FileHandle.standardOutput.write(contentsOf: Data((line + "\n").utf8)) }
                        } while final && changed
                        if final {
                            guard let result = record.exit else { throw RuriError.message("监控没有留下游戏退出结果。请查看运行记录并恢复中断状态。") }
                            let status = result.shellStatus
                            print("Game exit: \(status)")
                            if status != 0 { exit(status) }
                            break
                        }
                        if activity != .monitoring { throw RuriError.message("监控已断开，请检查运行记录；游戏可能仍在运行。") }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                } catch {
                    if !handedOff { try? recorder.fail(error, cancelled: Task.isCancelled) }
                    throw RuriError.message(recorder.redacted(error.localizedDescription))
                }
            case "quit":
                guard args.count == 2, let id = UUID(uuidString: args[1]) else { throw RuriError.message("用法：ruri-cli quit <instance-uuid>") }
                guard let record = try GameSessionStore.list(paths: paths, instanceID: id).first(where: { !$0.state.isFinished && GameMonitorClient.activity($0) == .monitoring }) else { throw RuriError.message("没有可连接的游戏监控进程。") }
                let request = try GameMonitorClient.requestNormalQuit(paths: paths, record: record)
                print("已提交正常退出请求：\(request)。这不代表游戏已经退出；监控会继续记录实际结果。")
            case "stop":
                guard args.count == 2, let id = UUID(uuidString: args[1]), try StateStore.load(paths).instances.contains(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli stop <instance-uuid>") }
                guard let record = try GameSessionStore.list(paths: paths, instanceID: id).first(where: { GameMonitorClient.activity($0) == .monitoring }) else { throw RuriError.message("没有可连接的游戏监控进程。") }
                try GameMonitorClient.requestStop(paths: paths, record: record)
                print("Stop requested: \(record.id)")
            case "recover-session":
                guard (3...5).contains(args.count), let instanceID = UUID(uuidString: args[1]), let sessionID = UUID(uuidString: args[2]),
                      Set(args.dropFirst(3)).isSubset(of: ["--apply", "--confirm-game-ended"]) else {
                    throw RuriError.message("用法：ruri-cli recover-session <instance-uuid> <session-uuid> [--apply] [--confirm-game-ended]")
                }
                let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
                let status = GameSessionRecovery.status(record)
                print(status.title + "\n" + status.explanation)
                if args.contains("--apply") {
                    let recovered = try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: args.contains("--confirm-game-ended"))
                    print(recovered.title)
                } else if status == .processEnded || status == .confirmationRequired {
                    print("使用 --apply 收尾这条记录；仅在已自行确认游戏退出时添加 --confirm-game-ended。")
                }
            case "diagnose":
                guard args.count == 3, let instanceID = UUID(uuidString: args[1]), let sessionID = UUID(uuidString: args[2]) else { throw RuriError.message("用法：ruri-cli diagnose <instance-uuid> <session-uuid>") }
                let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
                let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: record)
                print(diagnosis.title + "\n" + diagnosis.summary)
                for fact in diagnosis.facts { print("• " + fact) }
                for finding in diagnosis.findings {
                    print("\n\(finding.title)（\(finding.confidence.rawValue)）\n\(finding.explanation)")
                    for evidence in finding.evidence {
                        let document = diagnosis.documents.first { $0.id == evidence.documentID }
                        print("\(document?.title ?? evidence.documentID) · \(document?.isTail == true ? "末段" : "")第 \(evidence.line) 行\n\(evidence.excerpt)")
                    }
                    for (index, step) in finding.steps.enumerated() { print("\(index + 1). \(step)") }
                }
                for limitation in diagnosis.limitations { print("说明：" + limitation) }
            case "sessions":
                let state = try StateStore.load(paths)
                let instances: [GameInstance]
                if args.count > 1 {
                    guard let id = UUID(uuidString: args[1]), let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message("无效的实例 UUID") }
                    instances = [instance]
                } else { instances = state.instances }
                let records = try instances.flatMap { try GameSessionStore.list(paths: paths, instanceID: $0.id) }.sorted { $0.createdAt > $1.createdAt }
                for record in records { print("\(record.id) | \(record.createdAt.ISO8601Format()) | \(record.instanceName) | \(record.title)") }
            default: print("Ruri CLI\n  java\n  versions\n  install <version> [fabric|quilt|forge|neoforge]\n  install-java <major> [aarch64|x86_64]\n  repair <instance-uuid>\n  install-content <project> <instance-uuid> [version-id]\n  content <instance-uuid>\n  plan\n  sessions [instance-uuid]\n  diagnose <instance-uuid> <session-uuid>\n  recover-session <instance-uuid> <session-uuid> [--apply] [--confirm-game-ended]\n  launch [instance-uuid] [--detach] (offline account)\n  quit <instance-uuid> (normal application quit)\n  stop <instance-uuid> (SIGTERM)\n\nRURI_DATA_DIR overrides the data directory.")
            }
        } catch { fputs("Error: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
