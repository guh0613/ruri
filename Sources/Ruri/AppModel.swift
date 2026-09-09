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
    let basePaths: LauncherPaths
    let downloader = DownloadManager()
    var paths: LauncherPaths { basePaths.configured(with: state) }
    var installer: GameInstaller { GameInstaller(paths: paths, downloader: downloader) }
    var page = Page.home
    var catalog: VersionCatalog?
    var catalogLoading = false
    var catalogError: String?
    var runtimes: [JavaRuntime] = []
    var scanningJava = false
    var activities: [ActivityItem] = []
    var operation: Task<Void, Never>?
    var activeSessions: [UUID: GameSession] = [:]
    var runningID: UUID? { selected.flatMap { activeSessions[$0.id] }?.instanceID ?? activeSessions.values.max(by: { $0.createdAt < $1.createdAt })?.instanceID }
    var logs: [String] = []
    var showLogs = false
    var lastGameExit: GameExit?
    var crashReports: [GameCrashReport] = []
    var sessions: [GameSession] = []
    var logsSessionID: UUID?
    var liveLogs: [UUID: [String]] = [:]
    var requestedLogSessionID: UUID?
    var noticeSessionID: UUID?
    var restoringGames = true
    var isQuitting = false
    var pendingOpenURLs: [URL] = []
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
    @ObservationIgnored var monitorTask: Task<Void, Never>?
    @ObservationIgnored var logCursors: [UUID: GameSessionLogCursor] = [:]
    @ObservationIgnored var handledExits: Set<UUID> = []
    @ObservationIgnored var bootTask: Task<Void, Never>?
    var showCreate = false
    var showDirectories = false
    var directoryErrors: [UUID: String] = [:]
    var pendingDirectoryCopyIDs: Set<UUID> = []
    private var failedSessionReadIDs: Set<UUID> = []
    var showAccount = false
    var editingInstance: GameInstance?
    var contentInstance: GameInstance?
    var worldInstance: GameInstance?
    var curseForgeConfigured = CurseForgeKeyStore.isConfigured()
    var importingInstance: PreparedInstanceImport?
    var exportingInstance: GameInstance?
    var error: String?
    var notice: String? { didSet { noticeSessionID = nil; noticeFileURL = nil } }
    var noticeFileURL: URL?
    private var readOnly = false
    private var persistedState: PersistentState?
    private var sessionRecorder: GameSessionRecorder?
    private var recordingErrorShown = false
    var selected: GameInstance? { state.instances.first(where: { $0.id == state.selectedInstanceID }) ?? state.instances.first }
    var activeAccount: Account? { state.accounts.first { $0.id == state.activeAccountID } }
    var busy: Bool { operation != nil || restoringGames || isQuitting }
    var activeActivity: ActivityItem? { activities.first { $0.status == .running } }
    var selectedDirectoryID: UUID { state.selectedDirectoryID ?? GameDirectory.defaultID }
    var selectedDirectoryName: String { state.gameDirectories?.first(where: { $0.id == selectedDirectoryID })?.name ?? "默认实例文件夹" }
    var directoryInstances: [GameInstance] { state.instances.filter { ($0.directoryID ?? GameDirectory.defaultID) == selectedDirectoryID } }
    var colorScheme: ColorScheme? { state.settings.appearance == "dark" ? .dark : state.settings.appearance == "light" ? .light : nil }

    init() {
        let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        basePaths = LauncherPaths(root: root)
        do {
            state = try StateStore.load(basePaths)
            persistedState = state
            state.gameDirectories = state.gameDirectories?.map { $0.resolvingBookmark() }
            try basePaths.configured(with: state).validateDirectoryConfiguration()
        }
        catch { state = PersistentState(); self.error = "无法读取 Ruri 数据，已暂停写入以保护原文件。\n\(error.localizedDescription)"; readOnly = true }
    }
    func save() {
        guard !readOnly else { return }
        do { state = try StateStore.save(state, to: paths, basedOn: persistedState); persistedState = state }
        catch {
            readOnly = true
            self.error = "\(error.localizedDescription)\n已暂停本窗口的后续写入和安装/启动。请重新打开 Ruri 载入磁盘上的最新状态。"
        }
    }
    func boot() async {
        if let bootTask { await bootTask.value; return }
        let work = Task { await initializeApplication() }
        bootTask = work
        await work.value
    }
    private func initializeApplication() async {
        await refreshDirectoryAvailability()
        await refreshSessions()
        await pollGames()
        restoringGames = false
        startGameObservation()
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
        let extra = state.instances.compactMap { $0.resolvedLaunchSettings(defaults: state.settings).java.path } + [state.settings.defaultLaunchSettings.java.path].compactMap { $0 }
        runtimes = await JavaDiscovery.scan(paths: paths, extra: extra)
        scanningJava = false
    }
    func select(_ instance: GameInstance) { state.selectedInstanceID = instance.id; save() }
    func changeDirectory(_ work: (LauncherPaths) throws -> PersistentState) {
        guard !busy, !readOnly else { return }
        save()
        guard !readOnly else { return }
        do { state = try work(paths); persistedState = state; Task { await refreshDirectoryAvailability() } }
        catch { self.error = error.localizedDescription }
    }
    func refreshDirectoryAvailability() async {
        let directories = state.gameDirectories ?? []
        let errors = await Task.detached(priority: .utility) {
            var result: [UUID: String] = [:]
            for directory in directories {
                do { try directory.validateAvailability() } catch { result[directory.id] = error.localizedDescription }
            }
            return result
        }.value
        directoryErrors = errors.filter { id, _ in state.gameDirectories?.contains(where: { $0.id == id }) == true }
    }
    func update(_ instance: GameInstance) {
        guard let index = state.instances.firstIndex(where: { $0.id == instance.id }) else { return }
        state.instances[index] = instance; save()
    }
    func updateSettings(_ draft: GameInstance, basedOn original: GameInstance) {
        guard var current = state.instances.first(where: { $0.id == draft.id }) else { return }
        func apply<Value: Equatable>(_ key: WritableKeyPath<GameInstance, Value>) {
            if draft[keyPath: key] != original[keyPath: key] { current[keyPath: key] = draft[keyPath: key] }
        }
        apply(\.name); apply(\.favorite)
        var overrides = current.effectiveLaunchOverrides
        let desired = draft.effectiveLaunchOverrides, baseline = original.effectiveLaunchOverrides
        func setting<Value: Equatable>(_ key: WritableKeyPath<InstanceLaunchOverrides, Value>) {
            if desired[keyPath: key] != baseline[keyPath: key] { overrides[keyPath: key] = desired[keyPath: key] }
        }
        setting(\.memoryMB); setting(\.java); setting(\.jvmArguments); setting(\.gameArguments); setting(\.window)
        if overrides != current.effectiveLaunchOverrides { current.launchOverrides = overrides }
        update(current)
        Task { await scanJava() }
    }
    func updateDefaultLaunchSettings(_ draft: LaunchSettingsValues, basedOn original: LaunchSettingsValues) {
        var current = state.settings.defaultLaunchSettings
        func apply<Value: Equatable>(_ key: WritableKeyPath<LaunchSettingsValues, Value>) {
            if draft[keyPath: key] != original[keyPath: key] { current[keyPath: key] = draft[keyPath: key] }
        }
        apply(\.memoryMB); apply(\.java); apply(\.jvmArguments); apply(\.gameArguments); apply(\.window)
        state.settings.defaultLaunchSettings = current; save()
        Task { await scanJava() }
    }
    func changeGameRunDirectory(_ preview: GameRunDirectoryChangePreview, copyFiles: Bool = false) {
        perform("\(copyFiles ? "复制并切换" : "切换") \(preview.instanceName) 的运行目录") { [self] activity in
            let service = GameRunDirectoryChange(paths: paths)
            do {
                let result: RunDirectoryCopyResult?
                if copyFiles {
                    result = try await service.copyToEmpty(preview) { [weak self] value in Task { @MainActor in self?.progress(activity, value.progress) } }
                } else { _ = try await service.useExisting(preview); result = nil }
                state = try StateStore.load(basePaths); persistedState = state
                notice = result?.warning ?? "\(preview.instanceName) 已\(copyFiles ? "复制并切换" : "使用目标内容")；原目录及备份已保留。"
                noticeFileURL = result?.preservedCopy
            } catch let failure as RunDirectoryCopyFailure {
                notice = failure.localizedDescription; noticeFileURL = failure.preservedCopy
                throw failure
            }
        }
    }
    func recoverGameRunDirectory(_ pending: RunDirectoryCopyRecovery) {
        perform("恢复 \(pending.owner.instanceName) 的目录复制") { [self] _ in
            let result = try await GameRunDirectoryChange(paths: paths).recoverCopy(instanceID: pending.owner.instanceID, transactionID: pending.owner.transactionID)
            state = try StateStore.load(basePaths); persistedState = state
            notice = result.warning ?? (pending.committed ? "已清理完成的复制记录，目标内容保留。" : "已恢复到切换前的状态，复制工作区另行保留。")
            noticeFileURL = result.preservedCopy
        }
    }
    func install(name: String, version: String, loader: LoaderKind, loaderVersion: String?) {
        guard !busy, !readOnly else { return }
        var instance = GameInstance(name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Minecraft \(version)" : name, gameVersion: version, loader: loader, loaderVersion: loaderVersion)
        instance.launchOverrides = .init()
        instance.directoryID = paths.newInstanceDirectoryID
        instance.runDirectory = (state.settings.isolationPolicy ?? .always).directory(loader: loader)
        state.instances.append(instance); select(instance); showCreate = false; page = .downloads
        install(instance)
    }
    func install(_ instance: GameInstance) {
        guard !busy, !readOnly else { return }
        perform("安装 \(instance.name)", instanceID: instance.id) { [self] id in
            let result = try await installer.install(instance, concurrency: state.settings.concurrentDownloads) { [weak self] progress in
                await self?.progress(id, progress)
            }
            try recordInstallation(result, requested: instance); notice = "\(result.name) 已准备就绪"
        }
    }
    private func recordInstallation(_ result: GameInstance, requested: GameInstance) throws {
        save()
        guard !readOnly else { throw RuriError.message("设置写入已暂停，安装结果尚未登记。请重新载入后检查实例。") }
        state = try StateStore.update(basePaths) { latest in
            guard let index = latest.instances.firstIndex(where: { $0.id == result.id }) else { throw RuriError.message("实例已被移除，未重新登记。") }
            latest.instances[index] = try latest.instances[index].applyingInstallation(result, requested: requested)
        }
        persistedState = state
    }
    func repair(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id) else { return }
        perform("修复 \(instance.name)", instanceID: instance.id) { [self] id in
            try await installer.repair(instance, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
        }
    }
    func perform(_ title: String, presentErrors: Bool = true, instanceID: UUID? = nil, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        guard !busy, !readOnly else { return }
        let activity = ActivityItem(title: title); activities.insert(activity, at: 0)
        operation = Task {
            var lease: GameRunLease?
            defer { withExtendedLifetime(lease) {} }
            do {
                if let instanceID { lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID) }
                await applyNetworkSettings()
                try await work(activity.id)
                if let i = activities.firstIndex(where: { $0.id == activity.id }) { activities[i].status = .completed; activities[i].progress = InstallProgress("已完成", completed: 1, total: 1) }
            } catch {
                if let i = activities.firstIndex(where: { $0.id == activity.id }) {
                    activities[i].status = Task.isCancelled ? .cancelled : .failed
                    activities[i].error = error is RunDirectoryCopyFailure ? error.localizedDescription : Task.isCancelled ? "任务已取消。重试时会复用可用缓存，并尝试继续未完成的下载。" : error.localizedDescription
                }
                if !Task.isCancelled && (presentErrors || (instanceID != nil && lease == nil)) { self.error = error.localizedDescription }
            }
            operation = nil
        }
    }
    func applyNetworkSettings() async { await NetworkRouting.shared.configure(state.settings.downloadSource ?? .automatic) }
    func progress(_ id: UUID, _ progress: InstallProgress) {
        if let index = activities.firstIndex(where: { $0.id == id }), activities[index].status == .running { activities[index].progress = progress }
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
    func launch(_ requested: GameInstance) {
        guard !busy, !readOnly else { return }
        // Refresh/merge before taking a launch snapshot: another client may
        // have just committed a directory change while this window was idle.
        save()
        guard !readOnly, let stored = state.instances.first(where: { $0.id == requested.id }) else { return }
        guard !isInstanceInUse(stored.id) else { notice = "这个实例或共享目录正在使用中，请查看运行记录或实例设置中的恢复入口。"; return }
        guard var account = activeAccount else { showAccount = true; return }
        do {
            let defaults = state.settings
            let instance = try stored.launchSnapshot(defaults: defaults)
            let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: account.kind.rawValue)
            sessionRecorder = recorder; logsSessionID = recorder.record.id
            requestedLogSessionID = recorder.record.id
            let activeIDs = Set(activeSessions.values.map(\.id))
            liveLogs = liveLogs.filter { activeIDs.contains($0.key) }
            logs.removeAll(); lastGameExit = nil; crashReports = []; recordingErrorShown = false
            publishSession(recorder.record)
            perform("启动 \(instance.name)", presentErrors: false) { [self] id in
                do {
                    var instance = instance
                    try Task.checkCancellation()
                    if !instance.installed {
                        try advanceSession(.installation)
                        let installed = try await installer.install(stored, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                        try recordInstallation(installed, requested: stored)
                        instance = try installed.launchSnapshot(defaults: defaults)
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
                        var available = runtimes
                        if let path = instance.javaPath, !available.contains(where: { $0.path == path }) {
                            available.append(try await Task.detached(priority: .utility) { try JavaDiscovery.inspect(path) }.value)
                        }
                        java = try JavaDiscovery.select(from: available, major: requiredJava, architecture: architecture, preferredPath: instance.javaPath)
                    }
                    try Task.checkCancellation()
                    try recorder.setJava(java.label + " · " + java.version)
                    try advanceSession(.arguments)
                    try await installer.prepareRunDirectory(instance, manifest: manifest)
                    let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: token, paths: paths)
                    appendLog("[Ruri] \(java.label)")
                    appendLog("[Ruri] \(plan.redactedCommand)")
                    try advanceSession(.starting)
                    try GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [token])
                    sessionRecorder = nil
                    activeSessions[instance.id] = recorder.record
                    try? GameMonitorClient.recordEvent(.connected, paths: paths, session: recorder.record)
                    publishSession(recorder.record)
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
    func refreshSessions() async {
        await synchronizeExternalState()
        let ids = state.instances.map(\.id), paths = paths
        let result = await Task.detached(priority: .utility) {
            var records: [GameSession] = [], failures: [UUID: String] = [:], pending = Set<UUID>()
            for id in ids {
                do { records += try GameSessionStore.list(paths: paths, instanceID: id) } catch { failures[id] = error.localizedDescription }
                if RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: id) { pending.insert(id) }
            }
            return (records, failures, pending)
        }.value
        for record in result.0 {
            if let current = sessions.first(where: { $0.id == record.id }), current.updatedAt > record.updatedAt { continue }
            publishSession(record)
        }
        if pendingDirectoryCopyIDs != result.2 { pendingDirectoryCopyIDs = result.2 }
        let failures = Set(result.1.keys)
        if failures != failedSessionReadIDs, let message = result.1.values.first { notice = "部分运行记录暂时无法读取：\(message)" }
        failedSessionReadIDs = failures
        sessions.removeAll { !ids.contains($0.instanceID) }
        sessions.sort { $0.createdAt > $1.createdAt }
    }
    private func synchronizeExternalState() async {
        guard !readOnly, operation == nil else { return }
        let baselineRevision = persistedState?.revision, basePaths = basePaths
        do {
            let remote = try await Task.detached(priority: .utility) { try StateStore.load(basePaths) }.value
            // A local save may have completed while the disk read was running.
            guard operation == nil, persistedState?.revision == baselineRevision, remote.revision != baselineRevision else { return }
            if baselineRevision != nil && remote.revision == nil { throw RuriError.message("数据索引在外部被移除或替换，已暂停写入。请检查数据目录。") }
            if state == persistedState { state = remote; persistedState = remote }
            else { save() }
        } catch { readOnly = true; self.error = "无法同步其他客户端的更改，已暂停写入以保留原数据。\n\(error.localizedDescription)" }
    }
    func publishSession(_ record: GameSession) {
        if let index = sessions.firstIndex(where: { $0.id == record.id }) { if sessions[index] != record { sessions[index] = record } }
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
    private func appendDisplayedLog(_ line: String) {
        logs.append(line)
        if logs.count > 5000 { logs.removeFirst(logs.count - 5000) }
        if let id = logsSessionID { liveLogs[id] = logs }
    }
    func appendLog(_ line: String) {
        let line = sessionRecorder?.redacted(line) ?? line
        appendDisplayedLog(line)
        do { try sessionRecorder?.append(line) } catch { showRecordingError(error) }
    }
    func reveal(_ instance: GameInstance, folder: String? = nil) {
        let base = paths.game(instance.id)
        let url = folder.map { base.appendingPathComponent($0) } ?? base
        do { try paths.validateInstanceLocation(instance.id); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url) }
        catch { self.error = error.localizedDescription }
    }
    func trash(_ instance: GameInstance) {
        guard !isInstanceInUse(instance.id), !busy else { return }
        do {
            let lease = try GameRunLease.acquire(paths: paths, instanceID: instance.id)
            defer { withExtendedLifetime(lease) {} }
            let url = paths.instance(instance.id)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            state.instances.removeAll { $0.id == instance.id }
            if state.selectedInstanceID == instance.id { state.selectedInstanceID = state.instances.first?.id }
            save()
        } catch { self.error = error.localizedDescription }
    }
}
