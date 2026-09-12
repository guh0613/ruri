import RuriLocalization
import Foundation
import RuriCore

@main struct CLI {
    @MainActor static func main() async {
        if let status = LocalizationCommandLine.resourceCheck() { exit(status) }
        var arguments = Array(CommandLine.arguments.dropFirst())
        let language: String?
        do { language = try LocalizationCommandLine.takeLanguage(from: &arguments) }
        catch { fputs(error.localizedDescription + "\n", stderr); exit(2) }
        let context = language.map { LocalizationContext(language: $0) } ?? LocalizationContext.processDefault
        await LocalizationContext.$current.withValue(context) { await run(arguments) }
    }
    @MainActor private static func run(_ args: [String]) async {
        do {
            if args.first == "scan-minecraft" { try await scanMinecraft(args); return }
            let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            let basePaths = LauncherPaths(root: root)
            let paths = try basePaths.configured(with: StateStore.load(basePaths))
            let storedSource = (try? StateStore.load(paths).settings.downloadSource) ?? .automatic
            let source: DownloadSource
            if let requested = ProcessInfo.processInfo.environment["RURI_DOWNLOAD_SOURCE"] {
                guard let parsed = DownloadSource(rawValue: requested) else { throw RuriError.message(Messages.CLICLI.parsedText1) }
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
                guard args.count <= 2 else { throw RuriError.message(Messages.CLICLI.parsedText2) }
                if args.count == 2 {
                    guard let policy = GameIsolationPolicy(rawValue: args[1]) else { throw RuriError.message(Messages.CLICLI.policyText1) }
                    try StateStore.update(paths) { $0.settings.isolationPolicy = policy }
                }
                print((try StateStore.load(paths).settings.isolationPolicy ?? .always).title)
            case "run-directory":
                let usage = Messages.CLICLI.usageText1.localized
                guard (3...5).contains(args.count), let id = UUID(uuidString: args[1]), let mode = GameRunDirectory(rawValue: args[2]) else { throw RuriError.message(usage) }
                var remaining = Array(args.dropFirst(3))
                let action = remaining.last.flatMap { ["--apply", "--copy"].contains($0) ? $0 : nil }
                if action != nil { remaining.removeLast() }
                guard remaining.isEmpty || (mode == .custom && remaining.count == 1 && !remaining[0].hasPrefix("--")) else { throw RuriError.message(usage) }
                let currentState = try StateStore.load(paths)
                guard currentState.instances.contains(where: { $0.id == id }) else { throw RuriError.message(Messages.CLICLI.currentStateText1) }
                let custom = try remaining.first.map { try CustomRunDirectory.register(at: URL(fileURLWithPath: $0), paths: paths.configured(with: currentState)) }
                let service = GameRunDirectoryChange(paths: paths)
                let preview = try await service.preview(instanceID: id, target: mode, customDirectory: custom)
                print(Messages.CLICLI.previewText1(String(describing: preview.instanceName), String(describing: preview.sourceMode.title), String(describing: preview.targetMode.title), String(describing: preview.source.path), Int64(preview.sourceFileCount), String(describing: preview.sourceBytes), String(describing: preview.target.path), Int64(preview.targetFileCount), String(describing: preview.targetBytes)).localized)
                if !preview.otherInstances.isEmpty { print(Messages.CLICLI.sharedInstances(LocalizedFormat.list(preview.otherInstances)).localized) }
                if action == "--copy" {
                    let result = try await service.copyToEmpty(preview) { p in
                        if p.phase != .copying || p.completed % 50 == 0 {
                            try? FileHandle.standardOutput.write(contentsOf: Data("\(p.phase.rawValue) \(p.completed)/\(p.total) · \(p.bytesCopied)/\(p.totalBytes) bytes\n".utf8))
                        }
                    }
                    print(result.warning ?? Messages.CLICLI.resultText1.localized)
                    if let url = result.preservedCopy { print(Messages.CLICLI.urlText1(String(describing: url.path)).localized) }
                } else if action == "--apply" { _ = try await service.useExisting(preview); print(Messages.CLICLI.urlText2.localized) }
            case "recover-directory":
                guard (2...3).contains(args.count), let id = UUID(uuidString: args[1]), args.count == 2 || args[2] == "--apply" else { throw RuriError.message(Messages.CLICLI.idText1) }
                let service = GameRunDirectoryChange(paths: paths)
                guard let pending = try await service.pendingCopy(instanceID: id) else { print(Messages.CLICLI.pendingText1.localized); break }
                print(Messages.CLICLI.pendingText4(String(describing: pending.owner.instanceName), String(describing: pending.owner.transactionID), String(describing: pending.committed ? Messages.CLICLI.pendingText2.localized : Messages.CLICLI.pendingText3.localized), String(describing: pending.source.path), String(describing: pending.target.path)).localized)
                if args.count == 3 {
                    let result = try await service.recoverCopy(instanceID: pending.owner.instanceID, transactionID: pending.owner.transactionID)
                    print(result.warning ?? Messages.CLICLI.resultText2.localized)
                    if let url = result.preservedCopy { print(Messages.CLICLI.urlText1(String(describing: url.path)).localized) }
                }
            case "relocate-directory":
                guard (3...4).contains(args.count), let id = UUID(uuidString: args[1]), args.count == 3 || args[3] == "--apply" else { throw RuriError.message(Messages.CLICLI.idText2) }
                let service = CustomRunDirectoryRelocation(paths: paths)
                let preview = try await service.preview(instanceID: id, target: URL(fileURLWithPath: args[2]))
                print(Messages.CLICLI.previewText3(String(describing: preview.source.path), String(describing: preview.target.path)).localized)
                for item in preview.instances { print("  \(item.name) · \(item.usesDirectory ? Messages.CLICLI.previewText4.localized : Messages.CLICLI.previewText5.localized) · \(item.id)") }
                if args.count == 4 { _ = try await service.apply(preview); print(Messages.CLICLI.previewText6.localized) }
            case "copy-instance":
                let usage = Messages.CLICLI.usageText2.localized
                guard (4...7).contains(args.count), let id = UUID(uuidString: args[1]),
                      let directory = args[2] == "default" ? GameDirectory.defaultID : UUID(uuidString: args[2]) else { throw RuriError.message(usage) }
                let flags = Array(args.dropFirst(4))
                guard flags.allSatisfy({ ["--without-worlds", "--with-backups", "--apply"].contains($0) }), Set(flags).count == flags.count else { throw RuriError.message(usage) }
                let service = InstanceCopier(paths: paths)
                let preview = try await service.preview(instanceID: id, name: args[3], directoryID: directory, options: .init(includeWorlds: !flags.contains("--without-worlds"), includeBackups: flags.contains("--with-backups")))
                print(Messages.CLICLI.previewText7(String(describing: preview.source.name), String(describing: preview.copy.name), String(describing: preview.sourceGame.path), String(describing: preview.destination.path), Int64(preview.fileCount), String(describing: preview.bytes)).localized)
                if flags.contains("--apply") {
                    let result = try await service.copy(preview) { p in
                        if p.phase != .copying || p.completed % 50 == 0 { try? FileHandle.standardOutput.write(contentsOf: Data("\(p.phase.rawValue) \(p.completed)/\(p.total) · \(p.bytesCopied)/\(p.totalBytes) bytes\n".utf8)) }
                    }
                    print(Messages.CLICLI.resultText3(String(describing: preview.copy.id)).localized)
                    if let warning = result.warning { print(warning) }
                    if let file = result.preservedCopy { print(Messages.CLICLI.urlText1(String(describing: file.path)).localized) }
                }
            case "recover-instance-copy":
                guard (2...3).contains(args.count), let id = UUID(uuidString: args[1]), args.count == 2 || args[2] == "--apply" else { throw RuriError.message(Messages.CLICLI.idText3) }
                let service = InstanceCopier(paths: paths)
                guard let pending = try await service.pending(instanceID: id) else { print(Messages.CLICLI.pendingText5.localized); break }
                print(Messages.CLICLI.pendingText8(String(describing: pending.owner.sourceName), String(describing: pending.owner.copyName), String(describing: pending.owner.transactionID), String(describing: pending.committed ? Messages.CLICLI.pendingText6.localized : Messages.CLICLI.pendingText7.localized), String(describing: pending.destination.path), String(describing: pending.workspace.path)).localized)
                if args.count == 3 {
                    let result = try await service.recover(sourceID: pending.owner.sourceID, transactionID: pending.owner.transactionID)
                    print(result.warning ?? Messages.CLICLI.resultText4.localized)
                    if let file = result.preservedCopy { print(Messages.CLICLI.urlText1(String(describing: file.path)).localized) }
                }
            case "java", "add-java", "forget-java", "default-java", "repair-java", "remove-java":
                try await manageJava(args, paths: paths)
            case "install-java":
                guard args.count >= 2, let major = Int(args[1]) else { throw RuriError.message(Messages.CLICLI.majorText1) }
                let service = JavaInstaller(paths: paths)
                let architecture = args.count > 2 ? args[2] : JavaRuntime.hostArchitecture
                guard let runtime = try await service.available().first(where: { $0.major == major && $0.architecture == architecture }) else { throw RuriError.message(Messages.CLICLI.runtimeText1) }
                let installed = try await service.install(runtime, downloader: DownloadManager()) { p in
                    if p.completed % 20 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
                }
                print(Messages.CLICLI.installedText1(String(describing: installed.label), String(describing: installed.path)).localized)
            case "fetch":
                guard args.count >= 5, let url = URL(string: args[1]), let size = Int64(args[4]), size >= 0,
                      args[3].range(of: "^[a-fA-F0-9]{40}$", options: .regularExpression) != nil else { throw RuriError.message(Messages.CLICLI.sizeText1) }
                let item = DownloadItem(url: url, destination: URL(fileURLWithPath: args[2]), sha1: args[3], size: size)
                let manager = DownloadManager()
                try await manager.fetch(item) { p in print(Messages.CLICLI.managerText1(String(describing: p.receivedBytes), String(describing: p.totalBytes ?? size), String(describing: p.resumedBytes)).localized) }
                if let transfer = await manager.transfers().first { print(Messages.CLICLI.transferText1(String(describing: transfer.host), String(describing: transfer.attempt)).localized) }
                print(Messages.CLICLI.transferText2(String(describing: item.destination.lastPathComponent)).localized)
            case "versions":
                let catalog = try await GameInstaller(paths: paths).catalog()
                print(Messages.CLICLI.catalogText1(String(describing: catalog.latest.release)).localized)
                for version in catalog.versions.prefix(20) { print("\(version.id) [\(version.type)]") }
            case "install":
                guard (2...4).contains(args.count) else { throw RuriError.message(Messages.CLICLI.catalogText2) }
                guard let loader = args.count > 2 ? LoaderKind(rawValue: args[2]) : .vanilla else { throw RuriError.message(Messages.CLICLI.loaderText1) }
                var instance = GameInstance(name: "\(args[1]) \(loader.title)", gameVersion: args[1], loader: loader)
                if args.count == 4 { instance.loaderVersion = args[3] }
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
                print(Messages.CLICLI.leaseText1(String(describing: instance.id)).localized)
            case "export-instance":
                guard args.count >= 3, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CLICLI.instanceText1) }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                guard let format = args.count > 3 ? InstanceExportFormat(rawValue: args[3]) : .ruri else { throw RuriError.message(Messages.CLICLI.formatText1) }
                try await InstanceTransfer(paths: paths).export(instance, to: URL(fileURLWithPath: args[2]), format: format) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                print(Messages.CLICLI.formatText2(String(describing: instance.name)).localized)
            case "import-instance":
                guard args.count >= 2 else { throw RuriError.message(Messages.CLICLI.formatText3) }
                let transfer = InstanceTransfer(paths: paths)
                let prepared = try await transfer.prepare(URL(fileURLWithPath: args[1]))
                print(Messages.CLICLI.preparedText1(String(describing: prepared.format), String(describing: prepared.instance.subtitle), String(describing: prepared.fileCount)).localized)
                for warning in prepared.warnings { print(warning) }
                do {
                    let imported = try await transfer.install(prepared, name: args.count > 2 ? args[2] : prepared.instance.name, importJVMArguments: prepared.format == "MCBBS" || prepared.includesInstallation, installer: GameInstaller(paths: paths)) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                    if imported.repositoryVersionID == nil {
                        try StateStore.update(paths) { state in state.instances.append(imported); state.selectedInstanceID = imported.id }
                    }
                    await transfer.discard(prepared)
                    print(Messages.CLICLI.importedText1(String(describing: imported.id)).localized)
                } catch { await transfer.discard(prepared); throw error }
            case "update-pack", "rollback-pack", "recover-pack-update":
                try await manageModpackUpdate(args, paths: paths)
            case "components":
                guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else {
                    throw RuriError.message(Messages.CLICLI.instanceText2)
                }
                let service = InstanceComponents(paths: paths)
                if args.count == 2 {
                    print(instance.subtitle)
                    if let backup = try await service.backup(for: id) { print(Messages.CLICLI.backupText1(String(describing: backup.title)).localized) }
                    if let reason = InstanceComponents.unavailableReason(instance) { print(reason) }
                } else if args[2] == "versions", args.count == 4, let loader = LoaderKind(rawValue: args[3]) {
                    for version in try await GameInstaller(paths: paths).loaderVersions(loader, game: instance.gameVersion) { print(version) }
                } else if args[2] == "set", (4...5).contains(args.count), let loader = LoaderKind(rawValue: args[3]),
                          (loader == .vanilla ? args.count == 4 : args.count == 5) {
                    _ = try await service.change(instance, to: loader, version: args.count == 5 ? args[4] : nil) { p in
                        if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") }
                    }
                    print(Messages.CLICLI.loaderText2(String(describing: id)).localized)
                } else if args[2] == "restore", args.count == 3 {
                    _ = try await service.restore(instance); print(Messages.CLICLI.loaderText3(String(describing: id)).localized)
                } else { throw RuriError.message(Messages.CLICLI.instanceText2) }
            case "repair":
                guard args.count >= 2, let id = UUID(uuidString: args[1]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CLICLI.instanceText3) }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                try await GameInstaller(paths: paths).repair(instance) { p in if p.completed % 100 == 0 || p.completed == p.total { print("\(p.stage) \(p.completed)/\(p.total)") } }
                print(Messages.CLICLI.leaseText2(String(describing: instance.id)).localized)
            case "plan":
                let state = try StateStore.load(paths)
                guard args.count <= 2, args.count == 1 || UUID(uuidString: args[1]) != nil else { throw RuriError.message(Messages.CLICLI.stateText1) }
                let selectedID = args.count == 2 ? UUID(uuidString: args[1]) : state.selectedInstanceID
                guard let stored = selectedID.flatMap({ id in state.instances.first { $0.id == id } }) ?? (args.count == 1 ? state.instances.last : nil) else { throw RuriError.message(Messages.CLICLI.storedText1) }
                let instance = try stored.launchSnapshot(defaults: state.settings)
                let manifest = try await GameInstaller(paths: paths).loadManifest(instance)
                let runtimes = await JavaDiscovery.scan(paths: paths, extra: [instance.javaPath].compactMap { $0 })
                let java = try JavaDiscovery.select(from: runtimes, major: instance.preferredJavaMajor(default: manifest.requiredJava), architecture: GameInstaller.architecture(for: manifest), preferredPath: instance.javaPath)
                let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: Account(username: "RuriTest"), paths: paths)
                print(plan.redactedCommand)
                if let names = plan.customEnvironmentNames, !names.isEmpty { print(Messages.CLICLI.environmentNames(names.joined(separator: ", ")).localized) }
            case "install-content":
                guard args.count >= 3, let id = UUID(uuidString: args[2]), let instance = try StateStore.load(paths).instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CLICLI.instanceText4) }
                let lease = try GameRunLease.acquire(paths: paths, instanceID: id)
                defer { withExtendedLifetime(lease) {} }
                let service = ModrinthService()
                let versions = try await service.versions(project: args[1], game: instance.gameVersion, loader: instance.loader.modrinthLoader)
                guard let version = args.count > 3 ? versions.first(where: { $0.id == args[3] }) : versions.first else { throw RuriError.message(Messages.CLICLI.versionText1) }
                try await service.install(version: version, type: "mod", instance: instance, paths: paths, downloader: DownloadManager()) { p in print("\(p.stage) \(p.completed)/\(p.total)") }
                print(Messages.CLICLI.leaseText1(String(describing: version.version_number)).localized)
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
                    guard index + 1 < launchArgs.count else { throw RuriError.message(Messages.CLICLI.indexText1) }
                    worldFolder = launchArgs[index + 1]; launchArgs.removeSubrange(index...index + 1)
                }
                guard launchArgs.count <= 1 else { throw RuriError.message(Messages.CLICLI.indexText2) }
                let requestedID = launchArgs.first.flatMap(UUID.init(uuidString:)) ?? (launchArgs.isEmpty ? state.selectedInstanceID : nil)
                if !launchArgs.isEmpty && requestedID == nil { throw RuriError.message(Messages.CLICLI.requestedIDText1) }
                let selected = requestedID.flatMap { id in state.instances.first { $0.id == id } } ?? (launchArgs.isEmpty ? state.instances.last : nil)
                guard let stored = selected, let account = state.accounts.first(where: { $0.id == state.activeAccountID }) else { throw RuriError.message(Messages.CLICLI.accountText1) }
                guard account.kind == .offline else { throw RuriError.message(Messages.CLICLI.accountText2) }
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
                    print(Messages.CLICLI.planText1(String(describing: recorder.record.id)).localized)
                    if args.contains("--detach") { print(Messages.CLICLI.planText2.localized); break }
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
                            guard let result = record.exit else { throw RuriError.message(Messages.CLICLI.resultText5) }
                            let status = result.shellStatus
                            print(Messages.CLICLI.statusText1(String(describing: status)).localized)
                            if status != 0 { exit(status) }
                            break
                        }
                        if activity != .monitoring { throw RuriError.message(Messages.CLICLI.statusText2) }
                        try await Task.sleep(for: .milliseconds(250))
                    }
                } catch {
                    if !handedOff { try? recorder.fail(error, cancelled: Task.isCancelled) }
                    throw RuriError.message(recorder.redacted(error.localizedDescription))
                }
            case "quit":
                guard args.count == 2, let id = UUID(uuidString: args[1]) else { throw RuriError.message(Messages.CLICLI.idText4) }
                guard let record = try GameSessionStore.list(paths: paths, instanceID: id).first(where: { !$0.state.isFinished && GameMonitorClient.activity($0) == .monitoring }) else { throw RuriError.message(Messages.CLICLI.recordText1) }
                let request = try GameMonitorClient.requestNormalQuit(paths: paths, record: record)
                print(Messages.CLICLI.requestText1(String(describing: request)).localized)
            case "stop":
                guard args.count == 2, let id = UUID(uuidString: args[1]), try StateStore.load(paths).instances.contains(where: { $0.id == id }) else { throw RuriError.message(Messages.CLICLI.idText5) }
                guard let record = try GameSessionStore.list(paths: paths, instanceID: id).first(where: { GameMonitorClient.activity($0) == .monitoring }) else { throw RuriError.message(Messages.CLICLI.recordText1) }
                try GameMonitorClient.requestStop(paths: paths, record: record)
                print(Messages.CLICLI.recordText2(String(describing: record.id)).localized)
            case "recover-session":
                guard (3...5).contains(args.count), let instanceID = UUID(uuidString: args[1]), let sessionID = UUID(uuidString: args[2]),
                      Set(args.dropFirst(3)).isSubset(of: ["--apply", "--confirm-game-ended"]) else {
                    throw RuriError.message(Messages.CLICLI.sessionIDText1)
                }
                let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
                let status = GameSessionRecovery.status(record)
                print(status.title + "\n" + status.explanation)
                if args.contains("--apply") {
                    let recovered = try GameSessionRecovery.finish(paths: paths, expected: record, userConfirmedEnded: args.contains("--confirm-game-ended"))
                    print(recovered.title)
                } else if status == .processEnded || status == .confirmationRequired {
                    print(Messages.CLICLI.recoveredText1.localized)
                }
            case "diagnose":
                guard args.count == 3, let instanceID = UUID(uuidString: args[1]), let sessionID = UUID(uuidString: args[2]) else { throw RuriError.message(Messages.CLICLI.sessionIDText2) }
                let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
                let diagnosis = try GameDiagnosticAnalyzer.load(paths: paths, session: record)
                print(diagnosis.title + "\n" + diagnosis.summary)
                for fact in diagnosis.facts { print("• " + fact) }
                for finding in diagnosis.findings {
                    print("\n\(finding.title)（\(finding.confidence.title)）\n\(finding.explanation)")
                    for evidence in finding.evidence {
                        let document = diagnosis.documents.first { $0.id == evidence.documentID }
                        print(Messages.CLICLI.documentText2(String(describing: document?.title ?? evidence.documentID), String(describing: document?.isTail == true ? Messages.CLICLI.documentText1.localized : ""), String(describing: evidence.line), String(describing: evidence.excerpt)).localized)
                    }
                    for (index, step) in finding.steps.enumerated() { print("\(index + 1). \(step)") }
                }
                for limitation in diagnosis.limitations { print(Messages.CLICLI.diagnosticLimitation(limitation).localized) }
            case "sessions":
                let state = try StateStore.load(paths)
                let instances: [GameInstance]
                if args.count > 1 {
                    guard let id = UUID(uuidString: args[1]), let instance = state.instances.first(where: { $0.id == id }) else { throw RuriError.message(Messages.CLICLI.requestedIDText1) }
                    instances = [instance]
                } else { instances = state.instances }
                let records = try instances.flatMap { try GameSessionStore.list(paths: paths, instanceID: $0.id) }.sorted { $0.createdAt > $1.createdAt }
                for record in records { print("\(record.id) | \(record.createdAt.ISO8601Format()) | \(record.instanceName) | \(record.title)") }
            default: print(Messages.CLICLI.recordsText1.localized)
            }
        } catch { fputs(Messages.CLICLI.errorOutput(error.localizedDescription).localized, stderr); exit(1) }
    }
}
