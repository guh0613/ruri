import Foundation
import RuriCore

@main struct CLI {
    @MainActor static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.first == "scan-minecraft" { try await scanMinecraft(args); return }
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
            case "launch-settings":
                try manageLaunchSettings(Array(args.dropFirst()), paths: paths)
            case "move-instance", "recover-instance-move":
                try await manageInstanceMoves(args, paths: paths)
            case "directories":
                try manageDirectories(Array(args.dropFirst()), paths: paths)
            case "isolation-policy":
                guard args.count <= 2 else { throw RuriError.message("用法：ruri-cli isolation-policy [always|modded|never]") }
                if args.count == 2 {
                    guard let policy = GameIsolationPolicy(rawValue: args[1]) else { throw RuriError.message("隔离规则为 always、modded 或 never。") }
                    try StateStore.update(paths) { $0.settings.isolationPolicy = policy }
                }
                print((try StateStore.load(paths).settings.isolationPolicy ?? .always).title)
            case "run-directory":
                let usage = "用法：ruri-cli run-directory <实例UUID> <isolated|shared|custom> [自定义路径] [--apply|--copy]。默认预览；首次选择自定义路径会保存目录身份信息。--apply 使用现有内容；--copy 复制到空目标。原目录保留。"
                guard (3...5).contains(args.count), let id = UUID(uuidString: args[1]), let mode = GameRunDirectory(rawValue: args[2]) else { throw RuriError.message(usage) }
                var remaining = Array(args.dropFirst(3))
                let action = remaining.last.flatMap { ["--apply", "--copy"].contains($0) ? $0 : nil }
                if action != nil { remaining.removeLast() }
                guard remaining.isEmpty || (mode == .custom && remaining.count == 1 && !remaining[0].hasPrefix("--")) else { throw RuriError.message(usage) }
                let currentState = try StateStore.load(paths)
                guard currentState.instances.contains(where: { $0.id == id }) else { throw RuriError.message("这个实例已被移除，请刷新后重试。") }
                let custom = try remaining.first.map { try CustomRunDirectory.register(at: URL(fileURLWithPath: $0), paths: paths.configured(with: currentState)) }
                let service = GameRunDirectoryChange(paths: paths)
                let preview = try await service.preview(instanceID: id, target: mode, customDirectory: custom)
                print("\(preview.instanceName)：\(preview.sourceMode.title) → \(preview.targetMode.title)\n原目录：\(preview.source.path)\n\(preview.sourceFileCount) 个文件，\(preview.sourceBytes) 字节\n目标目录：\(preview.target.path)\n\(preview.targetFileCount) 个文件，\(preview.targetBytes) 字节")
                if !preview.otherInstances.isEmpty { print("共用目标目录的实例：" + preview.otherInstances.joined(separator: "、")) }
                if action == "--copy" {
                    let result = try await service.copyToEmpty(preview) { p in
                        if p.phase != .copying || p.completed % 50 == 0 {
                            try? FileHandle.standardOutput.write(contentsOf: Data("\(p.phase.rawValue) \(p.completed)/\(p.total) · \(p.bytesCopied)/\(p.totalBytes) bytes\n".utf8))
                        }
                    }
                    print(result.warning ?? "已复制并切换目录，原数据保留。")
                    if let url = result.preservedCopy { print("工作副本：\(url.path)") }
                } else if action == "--apply" { _ = try await service.useExisting(preview); print("已切换到目标现有内容，原目录及其文件已保留。") }
            case "recover-directory":
                guard (2...3).contains(args.count), let id = UUID(uuidString: args[1]), args.count == 2 || args[2] == "--apply" else { throw RuriError.message("用法：ruri-cli recover-directory <instance-uuid> [--apply]。默认只查看待恢复操作。") }
                let service = GameRunDirectoryChange(paths: paths)
                guard let pending = try await service.pendingCopy(instanceID: id) else { print("没有待恢复的运行目录复制。"); break }
                print("\(pending.owner.instanceName) · \(pending.owner.transactionID)\n\(pending.committed ? "复制已提交，只需清理记录" : "复制尚未提交，恢复会保留工作副本")\n原目录：\(pending.source.path)\n目标目录：\(pending.target.path)")
                if args.count == 3 {
                    let result = try await service.recoverCopy(instanceID: pending.owner.instanceID, transactionID: pending.owner.transactionID)
                    print(result.warning ?? "恢复完成。")
                    if let url = result.preservedCopy { print("工作副本：\(url.path)") }
                }
            case "relocate-directory":
                guard (3...4).contains(args.count), let id = UUID(uuidString: args[1]), args.count == 3 || args[3] == "--apply" else { throw RuriError.message("用法：ruri-cli relocate-directory <实例UUID> <原游戏目录的新路径> [--apply]。默认预览；只更新同一目录的引用，不移动或合并游戏文件。") }
                let service = CustomRunDirectoryRelocation(paths: paths)
                let preview = try await service.preview(instanceID: id, target: URL(fileURLWithPath: args[2]))
                print("原位置：\(preview.source.path)\n找回位置：\(preview.target.path)\n将更新以下实例：")
                for item in preview.instances { print("  \(item.name) · \(item.usesDirectory ? "正在使用此目录" : "记住的目录") · \(item.id)") }
                if args.count == 4 { _ = try await service.apply(preview); print("已更新目录引用，游戏文件原地保留。") }
            case "copy-instance":
                let usage = "用法：ruri-cli copy-instance <源实例UUID> <目标文件夹UUID|default> <副本名称> [--without-worlds] [--with-backups] [--apply]。默认预览，--apply 才复制。"
                guard (4...7).contains(args.count), let id = UUID(uuidString: args[1]),
                      let directory = args[2] == "default" ? GameDirectory.defaultID : UUID(uuidString: args[2]) else { throw RuriError.message(usage) }
                let flags = Array(args.dropFirst(4))
                guard flags.allSatisfy({ ["--without-worlds", "--with-backups", "--apply"].contains($0) }), Set(flags).count == flags.count else { throw RuriError.message(usage) }
                let service = InstanceCopier(paths: paths)
                let preview = try await service.preview(instanceID: id, name: args[3], directoryID: directory, options: .init(includeWorlds: !flags.contains("--without-worlds"), includeBackups: flags.contains("--with-backups")))
                print("\(preview.source.name) → \(preview.copy.name)\n源游戏目录：\(preview.sourceGame.path)\n副本位置：\(preview.destination.path)\n\(preview.fileCount) 个文件，\(preview.bytes) 字节\n副本使用独立运行目录；原实例保留。")
                if flags.contains("--apply") {
                    let result = try await service.copy(preview) { p in
                        if p.phase != .copying || p.completed % 50 == 0 { try? FileHandle.standardOutput.write(contentsOf: Data("\(p.phase.rawValue) \(p.completed)/\(p.total) · \(p.bytesCopied)/\(p.totalBytes) bytes\n".utf8)) }
                    }
                    print("Copied instance: \(preview.copy.id)")
                    if let warning = result.warning { print(warning) }
                    if let file = result.preservedCopy { print("工作副本：\(file.path)") }
                }
            case "recover-instance-copy":
                guard (2...3).contains(args.count), let id = UUID(uuidString: args[1]), args.count == 2 || args[2] == "--apply" else { throw RuriError.message("用法：ruri-cli recover-instance-copy <实例UUID> [--apply]。默认查看，--apply 恢复或清理复制。") }
                let service = InstanceCopier(paths: paths)
                guard let pending = try await service.pending(instanceID: id) else { print("没有待恢复的实例复制。"); break }
                print("\(pending.owner.sourceName) → \(pending.owner.copyName) · \(pending.owner.transactionID)\n\(pending.committed ? "副本已登记，等待校验和清理" : "副本未完成，恢复会保留工作区")\n目标：\(pending.destination.path)\n工作区：\(pending.workspace.path)")
                if args.count == 3 {
                    let result = try await service.recover(sourceID: pending.owner.sourceID, transactionID: pending.owner.transactionID)
                    print(result.warning ?? "已恢复实例复制。")
                    if let file = result.preservedCopy { print("工作副本：\(file.path)") }
                }
            case "java", "add-java", "forget-java", "default-java", "repair-java", "remove-java":
                try await manageJava(args, paths: paths)
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
                guard args.count >= 2 else { throw RuriError.message("用法：ruri-cli install <version> [fabric|quilt|forge|neoforge|legacyfabric|liteloader]") }
                guard let loader = args.count > 2 ? LoaderKind(rawValue: args[2]) : .vanilla else { throw RuriError.message("不支持的加载器名称") }
                var instance = GameInstance(name: "\(args[1]) \(loader.title)", gameVersion: args[1], loader: loader)
                instance.launchOverrides = .init()
                instance.directoryID = paths.newInstanceDirectoryID
                instance.runDirectory = (try StateStore.load(paths).settings.isolationPolicy ?? .always).directory(loader: loader)
                instance = try MinecraftFolderStore.preparingNewInstance(instance, paths: paths)
                let installPaths = paths.including(instance)
                let lease = try GameRunLease.acquire(paths: installPaths, instanceID: instance.id)
                defer { withExtendedLifetime(lease) {} }
                instance = try await GameInstaller(paths: installPaths).install(instance) { progress in
                    if progress.completed % 100 == 0 || progress.completed == progress.total { print("\(progress.stage) \(progress.completed)/\(progress.total)") }
                }
                try StateStore.update(paths) { state in state.instances.append(instance); state.selectedInstanceID = instance.id }
                print("Installed \(instance.id)")
            case "export-instance":
                guard args.count >= 3, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli export-instance <instance-uuid> <output.zip> [ruri|complete|multimc|mcbbs|mrpack]") }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                guard let format = args.count > 3 ? InstanceExportFormat(rawValue: args[3]) : .ruri else { throw RuriError.message("导出格式为 ruri、complete、multimc、mcbbs 或 mrpack") }
                try await InstanceTransfer(paths: paths).export(instance, to: URL(fileURLWithPath: args[2]), format: format) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                print("Exported \(instance.name)")
            case "import-instance":
                guard args.count >= 2 else { throw RuriError.message("用法：ruri-cli import-instance <folder-or-zip> [name]") }
                let transfer = InstanceTransfer(paths: paths)
                let prepared = try await transfer.prepare(URL(fileURLWithPath: args[1]))
                print("\(prepared.format): \(prepared.instance.subtitle), \(prepared.fileCount) files")
                for warning in prepared.warnings { print(warning) }
                do {
                    let imported = try await transfer.install(prepared, name: args.count > 2 ? args[2] : prepared.instance.name, importJVMArguments: prepared.format == "MCBBS" || prepared.includesInstallation, installer: GameInstaller(paths: paths)) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                    if imported.repositoryVersionID == nil {
                        try StateStore.update(paths) { state in state.instances.append(imported); state.selectedInstanceID = imported.id }
                    }
                    await transfer.discard(prepared)
                    print("Imported \(imported.id)")
                } catch { await transfer.discard(prepared); throw error }
            case "update-pack", "rollback-pack", "recover-pack-update":
                try await manageModpackUpdate(args, paths: paths)
            case "components":
                guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else {
                    throw RuriError.message("用法：ruri-cli components <instance-uuid> [versions <loader> | set <loader> [version] | restore]")
                }
                let service = InstanceComponents(paths: paths)
                if args.count == 2 {
                    print(instance.subtitle)
                    if let backup = try await service.backup(for: id) { print("Previous: \(backup.title)") }
                    if let reason = InstanceComponents.unavailableReason(instance) { print(reason) }
                } else if args[2] == "versions", args.count == 4, let loader = LoaderKind(rawValue: args[3]) {
                    for version in try await GameInstaller(paths: paths).loaderVersions(loader, game: instance.gameVersion) { print(version) }
                } else if args[2] == "set", (4...5).contains(args.count), let loader = LoaderKind(rawValue: args[3]),
                          (loader == .vanilla ? args.count == 4 : args.count == 5) {
                    _ = try await service.change(instance, to: loader, version: args.count == 5 ? args[4] : nil) { p in
                        if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
                    }
                    print("Updated components for \(id)")
                } else if args[2] == "restore", args.count == 3 {
                    _ = try await service.restore(instance); print("Restored components for \(id)")
                } else { throw RuriError.message("用法：ruri-cli components <instance-uuid> [versions <loader> | set <loader> [version] | restore]") }
            case "repair":
                guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli repair <instance-uuid>") }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                try await GameInstaller(paths: paths).repair(instance) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                print("Repaired \(instance.id)")
            case "plan":
                let state = try StateStore.load(paths)
                guard args.count <= 2, args.count == 1 || UUID(uuidString: args[1]) != nil else { throw RuriError.message("用法：ruri-cli plan [实例UUID]") }
                let selectedID = args.count == 2 ? UUID(uuidString: args[1]) : state.selectedInstanceID
                guard let stored = selectedID.flatMap({ id in state.instances.first { $0.id == id } }) ?? (args.count == 1 ? state.instances.last : nil) else { throw RuriError.message("没有找到指定实例") }
                let instance = try stored.launchSnapshot(defaults: state.settings)
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let runtimes = await JavaDiscovery.scan(paths: paths, extra: [instance.javaPath].compactMap { $0 })
                let java = try JavaDiscovery.select(from: runtimes, major: instance.preferredJavaMajor(default: manifest.requiredJava), architecture: GameInstaller.architecture(for: manifest), preferredPath: instance.javaPath)
                let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "RuriTest"), paths: paths)
                print(plan.redactedCommand)
                if let names = plan.customEnvironmentNames, !names.isEmpty { print("Environment overrides (values hidden): " + names.joined(separator: ", ")) }
            case "install-content":
                guard args.count >= 3, let id = UUID(uuidString: args[2]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message("用法：ruri-cli install-content <project> <instance-uuid> [version-id]") }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                let service = ModrinthService()
                let versions = try await service.versions(project: args[1], game: instance.gameVersion, loader: instance.loader.modrinthLoader)
                guard let version = args.count > 3 ? versions.first(where: { $0.id == args[3] }) : versions.first else { throw RuriError.message("找不到兼容内容版本") }
                try await service.install(version: version, type: "mod", instance: instance, paths: paths, downloader: DownloadManager()) { p in print("\(p.stage) \(p.completed)/\(p.total)") }
                print("Installed \(version.version_number)")
            case "content", "content-action", "update-content":
                try await manageContent(args, paths: paths)
            case "datapacks":
                try await manageDataPacks(args, paths: paths)
            case "schematics":
                try await manageSchematics(args, paths: paths)
            case "launch":
                let state = try StateStore.load(paths)
                var launchArgs = args.dropFirst().filter { $0 != "--detach" }
                var worldFolder: String?
                if let index = launchArgs.firstIndex(of: "--world") {
                    guard index + 1 < launchArgs.count else { throw RuriError.message("--world 后需要存档文件夹名。") }
                    worldFolder = launchArgs[index + 1]; launchArgs.removeSubrange(index...index + 1)
                }
                guard launchArgs.count <= 1 else { throw RuriError.message("用法：ruri-cli launch [instance-uuid] [--world 存档文件夹名] [--detach]") }
                let requestedID = launchArgs.first.flatMap(UUID.init(uuidString:)) ?? (launchArgs.isEmpty ? state.selectedInstanceID : nil)
                if !launchArgs.isEmpty && requestedID == nil { throw RuriError.message("无效的实例 UUID") }
                let selected = requestedID.flatMap { id in state.instances.first { $0.id == id } } ?? (launchArgs.isEmpty ? state.instances.last : nil)
                guard let stored = selected, let account = state.accounts.first(where: { $0.id == state.activeAccountID }) else { throw RuriError.message("请先安装实例并添加账号") }
                guard account.kind == .offline else { throw RuriError.message("命令行启动当前仅支持离线账号；Microsoft 或外置认证账号请在应用中启动。") }
                let recorder = try GameSessionRecorder(paths: paths, instance: stored, accountMode: account.kind.rawValue)
                var handedOff = false
                do {
                    let instance = try stored.launchSnapshot(defaults: state.settings)
                    try recorder.transition(.recovery)
                    try await ContentManager(paths: paths, instanceID: instance.id).recover()
                    try await WorldManager(paths: paths, instanceID: instance.id).recover()
                    try recorder.transition(.manifest)
                    let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                    let world = try worldFolder.map { folder in
                        try WorldQuickPlay.requireSupport(instance: instance, manifest: manifest)
                        return try WorldQuickPlay.selection(folder: folder, instanceID: instance.id, paths: paths)
                    }
                    try recorder.transition(.java)
                    let java = try JavaDiscovery.select(from: await JavaDiscovery.scan(paths: paths, extra: [instance.javaPath].compactMap { $0 }), major: instance.preferredJavaMajor(default: manifest.requiredJava), architecture: GameInstaller.architecture(for: manifest), preferredPath: instance.javaPath)
                    try recorder.setJava(java.label + " · " + java.version)
                    try recorder.transition(.arguments)
                    try await GameInstaller(paths: paths).prepareRunDirectory(instance, manifest: manifest)
                    let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, paths: paths, world: world)
                    recorder.addSecrets(plan.environmentRedactions)
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
            default: print("""
                Ruri CLI
                  java
                  add-java <Java executable or JDK folder>
                  forget-java <manually added executable path>
                  default-java <path or automatic>
                  repair-java <runtime-id>
                  remove-java <runtime-id> [--apply] [--reset-references] [--partial]
                  versions
                  install <version> [fabric|quilt|forge|neoforge]
                  install-java <major> [aarch64|x86_64]
                  repair <instance-uuid>
                  install-content <project> <instance-uuid> [version-id]
                  content <instance-uuid> [mod|resourcepack|shader]
                  content-action <instance-uuid> <kind> <enable|disable|remove> <filename ... | --all> [--apply]
                  plan [instance-uuid]
                  launch-settings <defaults|instance-uuid> [set <key> <value> | inherit <key|all>]
                  update-content <instance-uuid> <kind> [filename ... | --all] [--apply] [--manual <file-id> <path>]
                  schematics <instance-uuid> [list|info|import|mkdir|export|remove ...] [--apply]
                  directories <list|add|select|rename|relocate|remove> ...
                  run-directory <instance-uuid> <isolated|shared|custom> [path] [--apply|--copy]
                  recover-directory <instance-uuid> [--apply]
                  relocate-directory <instance-uuid> <original-folder-new-path> [--apply]
                  copy-instance <source-uuid> <directory-uuid|default> <name> [--without-worlds] [--with-backups] [--apply]
                  recover-instance-copy <instance-uuid> [--apply]
                  move-instance <instance-uuid> <directory-uuid|default> [--apply]
                  recover-instance-move <instance-uuid> [--apply] [--keep-source]
                  scan-minecraft <directory-or-version-json> [--json]
                  sessions [instance-uuid]
                  diagnose <instance-uuid> <session-uuid>
                  recover-session <instance-uuid> <session-uuid> [--apply] [--confirm-game-ended]
                  components <instance-uuid> [versions <loader> | set <loader> [version] | restore]
                  datapacks <instance-uuid> <world-folder> [import <path> | enable|disable|remove <filename>] [--apply]
                  update-pack <instance-uuid> <archive> [--apply] [--replace-local]
                  rollback-pack/recover-pack-update <instance-uuid> [--apply]
                  launch [instance-uuid] [--world folder] [--detach] (offline account)
                  quit <instance-uuid> (normal application quit)
                  stop <instance-uuid> (SIGTERM)

                RURI_DATA_DIR overrides the data directory.
                """)
            }
        } catch { fputs("Error: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
