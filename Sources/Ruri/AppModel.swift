import SwiftUI
import Observation
import AppKit
import RuriCore

struct ActivityItem: Identifiable {
    enum Status { case running, completed, failed, cancelled }
    let id = UUID()
    var title: String
    var progress = InstallProgress("准备中")
    var status = Status.running
    var error: String?
    let startedAt = Date()
}

enum Page: String, CaseIterable, Identifiable {
    case home, library, discover, downloads, accounts, java, settings
    var id: String { rawValue }
    var title: String { switch self { case .home: "开始游戏"; case .library: "游戏实例"; case .discover: "发现内容"; case .downloads: "下载任务"; case .accounts: "账号"; case .java: "Java 运行时"; case .settings: "设置" } }
    var symbol: String { switch self { case .home: "play.circle"; case .library: "square.grid.2x2"; case .discover: "safari"; case .downloads: "arrow.down.circle"; case .accounts: "person.crop.circle"; case .java: "cup.and.saucer"; case .settings: "gearshape" } }
}

@MainActor @Observable final class AppModel {
    var state: PersistentState
    let paths: LauncherPaths
    let installer: GameInstaller
    var page = Page.home
    var catalog: VersionCatalog?
    var catalogLoading = false
    var catalogError: String?
    var runtimes: [JavaRuntime] = []
    var scanningJava = false
    var activities: [ActivityItem] = []
    var operation: Task<Void, Never>?
    var runningID: UUID?
    var logs: [String] = []
    var showLogs = false
    var lastGameExit: GameExit?
    var crashReports: [GameCrashReport] = []
    var sessions: [GameSession] = []
    var logsSessionID: UUID?
    var showCreate = false
    var showAccount = false
    var editingInstance: GameInstance?
    var contentInstance: GameInstance?
    var worldInstance: GameInstance?
    var curseForgeConfigured = CurseForgeKeyStore.isConfigured()
    var importingInstance: PreparedInstanceImport?
    var exportingInstance: GameInstance?
    var error: String?
    var notice: String?
    private var readOnly = false
    private let gameProcess = GameProcess()
    private var sessionRecorder: GameSessionRecorder?
    private var recordingErrorShown = false
    var selected: GameInstance? { state.instances.first(where: { $0.id == state.selectedInstanceID }) ?? state.instances.first }
    var activeAccount: Account? { state.accounts.first { $0.id == state.activeAccountID } }
    var busy: Bool { operation != nil }
    var activeActivity: ActivityItem? { activities.first { $0.status == .running } }
    var colorScheme: ColorScheme? { state.settings.appearance == "dark" ? .dark : state.settings.appearance == "light" ? .light : nil }

    init() {
        let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        paths = LauncherPaths(root: root); installer = GameInstaller(paths: paths)
        do { state = try StateStore.load(paths) }
        catch { state = PersistentState(); self.error = "无法读取 Ruri 数据，已暂停写入以保护原文件。\n\(error.localizedDescription)"; readOnly = true }
    }
    func save() {
        guard !readOnly else { return }
        do { try StateStore.save(state, to: paths) } catch { self.error = error.localizedDescription }
    }
    func boot() async {
        refreshSessions()
        await applyNetworkSettings()
        async let versions: () = refreshCatalog()
        async let java: () = scanJava()
        _ = await (versions, java)
    }
    func refreshCatalog() async {
        guard !catalogLoading else { return }
        catalogLoading = true; catalogError = nil
        defer { catalogLoading = false }
        do { catalog = try await installer.catalog() } catch { catalogError = error.localizedDescription }
    }
    func scanJava() async {
        guard !scanningJava else { return }
        scanningJava = true
        runtimes = await JavaDiscovery.scan(paths: paths, extra: state.instances.compactMap(\.javaPath))
        scanningJava = false
    }
    func select(_ instance: GameInstance) { state.selectedInstanceID = instance.id; save() }
    func update(_ instance: GameInstance) {
        guard let index = state.instances.firstIndex(where: { $0.id == instance.id }) else { return }
        state.instances[index] = instance; save()
    }
    func install(name: String, version: String, loader: LoaderKind, loaderVersion: String?) {
        guard !busy, !readOnly else { return }
        var instance = GameInstance(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Minecraft \(version)" : name, gameVersion: version, loader: loader, loaderVersion: loaderVersion)
        instance.memoryMB = state.settings.defaultMemoryMB
        state.instances.append(instance); select(instance); showCreate = false; page = .downloads
        install(instance)
    }
    func install(_ instance: GameInstance) {
        guard !busy, !readOnly else { return }
        perform("安装 \(instance.name)") { [self] id in
            let result = try await installer.install(instance, concurrency: state.settings.concurrentDownloads) { [weak self] progress in
                await self?.progress(id, progress)
            }
            update(result); notice = "\(result.name) 已准备就绪"
        }
    }
    func repair(_ instance: GameInstance) {
        guard runningID != instance.id else { return }
        perform("修复 \(instance.name)") { [self] id in
            try await installer.repair(instance, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
        }
    }
    func perform(_ title: String, presentErrors: Bool = true, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        guard !busy, !readOnly else { return }
        let activity = ActivityItem(title: title); activities.insert(activity, at: 0)
        operation = Task {
            do {
                await applyNetworkSettings()
                try await work(activity.id)
                if let i = activities.firstIndex(where: { $0.id == activity.id }) { activities[i].status = .completed; activities[i].progress = InstallProgress("已完成", completed: 1, total: 1) }
            } catch {
                if let i = activities.firstIndex(where: { $0.id == activity.id }) {
                    activities[i].status = Task.isCancelled ? .cancelled : .failed
                    activities[i].error = Task.isCancelled ? "任务已取消。重试时会复用可用缓存，并尝试继续未完成的下载。" : error.localizedDescription
                }
                if !Task.isCancelled && presentErrors { self.error = error.localizedDescription }
            }
            operation = nil
        }
    }
    func applyNetworkSettings() async { await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic) }
    func progress(_ id: UUID, _ progress: InstallProgress) {
        if let index = activities.firstIndex(where: { $0.id == id }) { activities[index].progress = progress }
    }
    func addOffline(_ username: String) throws {
        let account = try Account(username: username)
        guard !state.accounts.contains(where: { $0.uuid == account.uuid }) else { throw RuriError.message("这个离线账号已存在。") }
        state.accounts.append(account); state.activeAccountID = account.id; save()
    }
    func addMicrosoft(_ account: Account, credentials: AccountCredentials) throws {
        var account = account
        if let existing = state.accounts.first(where: { $0.kind == .microsoft && $0.uuid == account.uuid }) { account.id = existing.id }
        try CredentialStore.save(credentials, for: account.id)
        state.accounts.removeAll { $0.id == account.id }; state.accounts.append(account); state.activeAccountID = account.id; save()
    }
    func removeAccount(_ account: Account) {
        do {
            if account.kind == .microsoft { try CredentialStore.remove(for: account.id) }
            state.accounts.removeAll { $0.id == account.id }
            if state.activeAccountID == account.id { state.activeAccountID = state.accounts.first?.id }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func launch(_ instance: GameInstance) {
        guard runningID == nil, !busy, !readOnly else { return }
        guard var account = activeAccount else { showAccount = true; return }
        do {
            let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: account.kind.rawValue)
            sessionRecorder = recorder; logsSessionID = recorder.record.id
            logs.removeAll(); lastGameExit = nil; crashReports = []; recordingErrorShown = false
            publishSession(recorder.record)
            perform("启动 \(instance.name)", presentErrors: false) { [self] id in
                do {
                    var instance = instance
                    try Task.checkCancellation()
                    if !instance.installed {
                        try advanceSession(.installation)
                        instance = try await installer.install(instance, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                        update(instance)
                    }
                    try advanceSession(.recovery)
                    try await ContentManager(paths: paths, instanceID: instance.id).recover()
                    try await WorldManager(paths: paths, instanceID: instance.id).recover()
                    try advanceSession(.account)
                    progress(id, InstallProgress("正在检查账号和 Java"))
                    var token = "0"
                    if account.kind == .microsoft {
                        var credentials = try CredentialStore.load(for: account.id)
                        recorder.addSecrets([credentials.accessToken, credentials.refreshToken])
                        if credentials.expiresAt < Date().addingTimeInterval(120) {
                            (account, credentials) = try await MicrosoftAuth(clientID: credentials.clientID).refresh(credentials, account: account)
                            recorder.addSecrets([credentials.accessToken, credentials.refreshToken])
                            try addMicrosoft(account, credentials: credentials)
                        }
                        token = credentials.accessToken
                    }
                    try advanceSession(.manifest)
                    let manifest = try await installer.loadManifest(instance)
                    let architecture = GameInstaller.architecture(for: manifest)
                    let requiredJava = try instance.preferredJavaMajor(default: manifest.requiredJava)
                    try advanceSession(.java)
                    let java: JavaRuntime
                    if instance.javaPath == nil, !runtimes.contains(where: { $0.major == requiredJava && $0.architecture == architecture }) {
                        let service = JavaInstaller(paths: paths)
                        progress(id, InstallProgress("正在准备所需的 Java \(requiredJava)"))
                        guard let runtime = try await service.available().first(where: { $0.major == requiredJava && $0.architecture == architecture }) else {
                            throw RuriError.message("Mojang 未提供此版本需要的 Java，请到 Java 运行时页面手动安装。")
                        }
                        java = try await service.install(runtime, downloader: installer.downloader) { [weak self] p in await self?.progress(id, p) }
                        await scanJava()
                    } else {
                        java = try JavaDiscovery.select(from: runtimes, major: requiredJava, architecture: architecture, preferredPath: instance.javaPath)
                    }
                    try Task.checkCancellation()
                    try recorder.setJava(java.label + " · " + java.version)
                    try advanceSession(.arguments)
                    let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: token, paths: paths)
                    appendLog("[Ruri] \(java.label)")
                    appendLog("[Ruri] \(plan.redactedCommand)")
                    try advanceSession(.starting)
                    let instanceID = instance.id
                    try gameProcess.start(plan: plan, secrets: [token]) { [weak self] line in self?.appendLog(line) } onExit: { [weak self] result in self?.gameExited(instanceID, result: result) }
                    runningID = instance.id
                    if let pid = gameProcess.processIdentifier {
                        do { try recorder.started(processID: pid) } catch { showRecordingError(error) }
                        publishSession(recorder.record)
                    }
                    var updated = instance; updated.lastPlayed = Date(); update(updated)
                } catch {
                    do { try recorder.fail(error, cancelled: Task.isCancelled) } catch { showRecordingError(error) }
                    publishSession(recorder.record)
                    if let failure = recorder.record.failure { appendDisplayedLog("[Ruri] \(failure)") }
                    sessionRecorder = nil
                    if !Task.isCancelled { showLogs = true; notice = recorder.record.title + "，可在运行记录中查看详情。" }
                    throw RuriError.message(recorder.redacted(error.localizedDescription))
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    func refreshSessions() {
        do {
            sessions = try state.instances.flatMap { try GameSessionStore.list(paths: paths, instanceID: $0.id) }.sorted { $0.createdAt > $1.createdAt }
        } catch { notice = "无法读取运行记录：\(error.localizedDescription)" }
    }
    private func publishSession(_ record: GameSession) {
        if let index = sessions.firstIndex(where: { $0.id == record.id }) { sessions[index] = record }
        else { sessions.insert(record, at: 0) }
    }
    private func advanceSession(_ stage: GameSession.Stage) throws {
        try sessionRecorder?.transition(stage)
        appendDisplayedLog("[Ruri] \(stage.title)")
        if let record = sessionRecorder?.record { publishSession(record) }
    }
    private func showRecordingError(_ error: any Error) {
        guard !recordingErrorShown else { return }
        recordingErrorShown = true
        let message = "运行记录未能完整写入：\(sessionRecorder?.redacted(error.localizedDescription) ?? error.localizedDescription)"
        notice = message; appendDisplayedLog("[Ruri] \(message)")
    }
    func stopGame() {
        guard gameProcess.isRunning else { return }
        do { try advanceSession(.stopping) } catch { showRecordingError(error) }
        gameProcess.stop()
    }
    private func appendDisplayedLog(_ line: String) {
        logs.append(line)
        if logs.count > 5000 { logs.removeFirst(logs.count - 5000) }
    }
    func appendLog(_ line: String) {
        let line = sessionRecorder?.redacted(line) ?? line
        appendDisplayedLog(line)
        do { try sessionRecorder?.append(line) } catch { showRecordingError(error) }
    }
    private func gameExited(_ id: UUID, result: GameExit) {
        lastGameExit = result
        crashReports = GameCrashReport.find(in: paths.game(id), exit: result)
        appendDisplayedLog(result.logDescription)
        appendDisplayedLog("[Ruri] \(result.explanation)")
        if let recorder = sessionRecorder {
            do { try recorder.finish(exit: result) } catch { showRecordingError(error) }
            publishSession(recorder.record)
        }
        do { try result.save(paths: paths, instanceID: id) }
        catch { showRecordingError(error) }
        sessionRecorder = nil; runningID = nil
        if var instance = state.instances.first(where: { $0.id == id }) {
            instance.playTime += result.endedAt.timeIntervalSince(result.startedAt); update(instance)
        }
        if result.requiresAttention || !crashReports.isEmpty { showLogs = true; notice = result.summary + "，请查看运行日志。" }
    }
    func reveal(_ instance: GameInstance, folder: String? = nil) {
        let base = paths.game(instance.id)
        let url = folder.map { base.appendingPathComponent($0) } ?? base
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url) }
        catch { self.error = error.localizedDescription }
    }
    func trash(_ instance: GameInstance) {
        guard runningID != instance.id, !busy else { return }
        do {
            let url = paths.instance(instance.id)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            state.instances.removeAll { $0.id == instance.id }
            if state.selectedInstanceID == instance.id { state.selectedInstanceID = state.instances.first?.id }
            save()
        } catch { self.error = error.localizedDescription }
    }
}
