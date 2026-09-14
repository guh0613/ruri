import RuriLocalization
import SwiftUI
import Observation
import AppKit
import RuriCore

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
    var javaEntries: [JavaRuntimeEntry] = []
    var scanningJava = false
    var javaScanAgain = false
    var journal = LauncherJournal()
    var journalStorageError: String?
    var selectedLogID: UUID?
    var logNavigationID = UUID()
    var journalPersistenceEnabled = true
    @ObservationIgnored var journalWriteTask: Task<Void, Never>?
    @ObservationIgnored var journalCheckpoint = Date.distantPast
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
    var restoringGames = true
    var isQuitting = false
    var pendingOpenURLs: [URL] = []
    @ObservationIgnored var openMainWindow: (@MainActor () -> Void)?
    @ObservationIgnored var monitorTask: Task<Void, Never>?
    @ObservationIgnored var logCursors: [UUID: GameSessionLogCursor] = [:]
    @ObservationIgnored var handledExits: Set<UUID> = []
    @ObservationIgnored var launchPresentations: [UUID: LaunchPresentation] = [:]
    @ObservationIgnored var automaticallyHiddenSessions: Set<UUID> = []
    @ObservationIgnored var bootTask: Task<Void, Never>?
    var showCreate = false
    var showDirectories = false
    var directoryErrors: [UUID: String] = [:]
    var customDirectoryErrors: [UUID: String] = [:]
    var pendingDirectoryCopyIDs: Set<UUID> = []
    var pendingInstanceCopyIDs: Set<UUID> = []
    var pendingInstanceMoveIDs: Set<UUID> = []
    var failedSessionReadIDs: Set<UUID> = []
    var showAccount = false
    var editingInstance: GameInstance?
    var contentInstance: GameInstance?
    var worldInstance: GameInstance?
    var schematicInstance: GameInstance?
    var curseForgeConfigured = CurseForgeKeyStore.isConfigured()
    var importingInstance: PreparedInstanceImport?
    var exportingInstance: GameInstance?
    var copyingInstance: GameInstance?
    var movingInstance: GameInstance?
    var error: String? {
        didSet {
            if let error, !journal.entries.contains(where: { $0.id == LauncherActivityContext.id && $0.status == .failed }) {
                report(error, level: .error)
            }
        }
    }
    private(set) var readOnly = false
    private(set) var persistedState: PersistentState?
    var sessionRecorder: GameSessionRecorder?
    var recordingErrorShown = false
    var selected: GameInstance? { directoryInstances.first(where: { $0.id == state.selectedInstanceID }) ?? directoryInstances.first }
    var activeAccount: Account? { state.accounts.first { $0.id == state.activeAccountID } }
    var busy: Bool { operation != nil || restoringGames || isQuitting }
    var activeActivity: LauncherLogEntry? { journal.entries.first { $0.status == .running } }
    var selectedDirectoryID: UUID { state.selectedDirectoryID ?? GameDirectory.defaultID }
    var selectedDirectoryName: String { state.gameDirectories?.first(where: { $0.id == selectedDirectoryID })?.name ?? Messages.AppAppModel.defaultInstanceDirectory.localized }
    var directoryInstances: [GameInstance] { state.instances.filter { ($0.directoryID ?? GameDirectory.defaultID) == selectedDirectoryID } }
    var colorScheme: ColorScheme? { state.settings.appearance == "dark" ? .dark : state.settings.appearance == "light" ? .light : nil }

    init() {
        let root = ProcessInfo.processInfo.environment["RURI_DATA_DIR"].map { URL(fileURLWithPath: $0) }
        basePaths = LauncherPaths(root: root)
        do {
            state = try StateStore.load(basePaths)
            persistedState = state
            try basePaths.configured(with: state).validateDirectoryConfiguration()
        }
        catch { state = PersistentState(); self.error = Messages.AppAppModel.unreadableData(error.localizedDescription).localized; readOnly = true }
        do {
            journal = try LauncherJournal.load(from: journalURL)
            journal.recoverInterrupted()
        } catch {
            journalPersistenceEnabled = false
            journalStorageError = Messages.LauncherLog.historyUnavailable.localized
            journal.record(Messages.LauncherLog.historyReadError(error.localizedDescription), level: .warning)
        }
        journal.record(Messages.LauncherLog.ready, notify: false)
        if let error { journal.record(.verbatim(error), level: .error) }
        persistJournal()
    }
    func save() {
        guard !readOnly else { return }
        do { state = try StateStore.save(state, to: paths, basedOn: persistedState); persistedState = state }
        catch {
            readOnly = true
            self.error = Messages.AppAppModel.savePaused(error.localizedDescription).localized
        }
    }
    func boot() async {
        if let bootTask { await bootTask.value; return }
        let work = Task { await initializeApplication() }
        bootTask = work
        await work.value
    }
    private func initializeApplication() async {
        if !readOnly {
            do {
                let basePaths = basePaths
                _ = try await Task.detached(priority: .utility) { try GameDirectoryStore.resolveBookmarks(paths: basePaths) }.value
                state = try await CustomRunDirectoryRelocation(paths: basePaths).resolveBookmarks(); persistedState = state
            } catch { self.error = Messages.AppAppModel.directoryRecoveryFailed(error.localizedDescription).localized }
        }
        if !readOnly {
            let base = basePaths, id = selectedDirectoryID
            do { acceptState(try await Task.detached(priority: .utility) { try MinecraftFolderStore.refresh(id, paths: base) }.value) }
            catch { directoryErrors[id] = error.localizedDescription }
        }
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
    func perform(_ title: String, presentErrors: Bool = true, instanceID: UUID? = nil, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        perform(.verbatim(title), presentErrors: presentErrors, instanceID: instanceID, work: work)
    }
    func perform(_ title: LocalizedMessage, presentErrors: Bool = true, instanceID: UUID? = nil, work: @escaping @MainActor @Sendable (UUID) async throws -> Void) {
        guard !busy, !readOnly else { return }
        let id = journal.begin(title)
        persistJournal()
        operation = Task {
            await LauncherActivityContext.$id.withValue(id) {
                var lease: GameRunLease?
                defer { withExtendedLifetime(lease) {} }
                do {
                    if let instanceID { lease = try GameRunLease.acquire(paths: paths, instanceID: instanceID) }
                    await applyNetworkSettings()
                    try await work(id)
                    journal.finish(id, status: .completed)
                } catch {
                    let cancelled = Task.isCancelled || error is CancellationError
                    let detail = error is RunDirectoryCopyFailure || error is InstanceMoveFailure || error is RepositoryImportFailure ? error.localizedDescription : cancelled ? Messages.AppAppModel.taskCancelled.localized : error.localizedDescription
                    journal.finish(id, status: cancelled ? .cancelled : .failed, detail: detail)
                    if !cancelled && (presentErrors || (instanceID != nil && lease == nil)) { self.error = error.localizedDescription }
                }
                persistJournal()
                operation = nil
            }
        }
    }
    func progress(_ id: UUID, _ progress: InstallProgress) {
        journal.progress(id, progress)
        if Date().timeIntervalSince(journalCheckpoint) >= 5 {
            journalCheckpoint = Date()
            persistJournal()
        }
    }
    func synchronizeExternalState() async {
        guard !readOnly, operation == nil else { return }
        let baselineRevision = persistedState?.revision, basePaths = basePaths
        do {
            let remote = try await Task.detached(priority: .utility) { try StateStore.load(basePaths) }.value
            // A local save may have completed while the disk read was running.
            guard operation == nil, persistedState?.revision == baselineRevision, remote.revision != baselineRevision else { return }
            if baselineRevision != nil && remote.revision == nil { throw RuriError.message(Messages.AppAppModel.externalIndexChanged) }
            if state == persistedState { state = remote; persistedState = remote }
            else { save() }
        } catch { readOnly = true; self.error = Messages.AppAppModel.externalChangesDetected(error.localizedDescription).localized }
    }
    /// Accept a state already committed by a core service, keeping the merge
    /// baseline in sync without exposing a writable baseline to feature code.
    func acceptState(_ saved: PersistentState) {
        state = saved
        persistedState = saved
    }
}
