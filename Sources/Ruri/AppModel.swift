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
    var showCreate = false
    var showAccount = false
    var editingInstance: GameInstance?
    var error: String?
    var notice: String?
    private var readOnly = false
    private let gameProcess = GameProcess()
    private var logFile: FileHandle?
    private var startedAt: Date?
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
    func perform(_ title: String, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        guard !busy, !readOnly else { return }
        let activity = ActivityItem(title: title); activities.insert(activity, at: 0)
        operation = Task {
            do {
                try await work(activity.id)
                if let i = activities.firstIndex(where: { $0.id == activity.id }) { activities[i].status = .completed; activities[i].progress = InstallProgress("已完成", completed: 1, total: 1) }
            } catch {
                if let i = activities.firstIndex(where: { $0.id == activity.id }) {
                    activities[i].status = Task.isCancelled ? .cancelled : .failed
                    activities[i].error = Task.isCancelled ? "任务已取消，已校验的文件保留以便重试。" : error.localizedDescription
                }
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
            operation = nil
        }
    }
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
        guard runningID == nil, !busy else { return }
        guard var account = activeAccount else { showAccount = true; return }
        guard instance.installed else { install(instance); return }
        perform("启动 \(instance.name)") { [self] id in
            progress(id, InstallProgress("正在检查账号和 Java"))
            var token = "0"
            if account.kind == .microsoft {
                var credentials = try CredentialStore.load(for: account.id)
                if credentials.expiresAt < Date().addingTimeInterval(120) {
                    (account, credentials) = try await MicrosoftAuth(clientID: credentials.clientID).refresh(credentials, account: account)
                    try addMicrosoft(account, credentials: credentials)
                }
                token = credentials.accessToken
            }
            let manifest = try await installer.loadManifest(instance)
            let java = try JavaDiscovery.select(from: runtimes, major: manifest.requiredJava, architecture: GameInstaller.architecture(for: manifest), preferredPath: instance.javaPath)
            let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: token, paths: paths)
            logs.removeAll()
            let logURL = paths.instance(instance.id).appendingPathComponent("launcher.log")
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            logFile = try FileHandle(forWritingTo: logURL)
            appendLog("[Ruri] \(java.label)")
            appendLog("[Ruri] \(plan.redactedCommand)")
            try gameProcess.start(plan: plan, secrets: [token]) { [weak self] line in self?.appendLog(line) } onExit: { [weak self] status in self?.gameExited(instance.id, status: status) }
            runningID = instance.id; startedAt = Date()
            var updated = instance; updated.lastPlayed = Date(); update(updated)
        }
    }
    func stopGame() { gameProcess.stop() }
    func appendLog(_ line: String) {
        logs.append(line)
        if logs.count > 5000 { logs.removeFirst(logs.count - 5000) }
        try? logFile?.write(contentsOf: Data((line + "\n").utf8))
    }
    private func gameExited(_ id: UUID, status: Int32) {
        appendLog("[Ruri] 游戏已退出，状态码 \(status)")
        try? logFile?.close(); logFile = nil; runningID = nil
        if var instance = state.instances.first(where: { $0.id == id }), let startedAt {
            instance.playTime += Date().timeIntervalSince(startedAt); update(instance)
        }
        if status != 0 && status != 15 { showLogs = true; notice = "游戏异常退出，请查看日志中的错误信息。" }
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
