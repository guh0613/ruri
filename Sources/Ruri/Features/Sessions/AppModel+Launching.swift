import RuriLocalization
import Foundation
import RuriCore

extension AppModel {
    func launch(_ requested: GameInstance, world: WorldSnapshot? = nil) {
        guard !busy, !readOnly else { return }
        // Refresh/merge before taking a launch snapshot: another client may
        // have just committed a directory change while this window was idle.
        save()
        guard !readOnly, let stored = state.instances.first(where: { $0.id == requested.id }) else { return }
        guard !isInstanceInUse(stored.id) else { report(Messages.AppAppModelLaunching.instanceInUse, level: .warning); return }
        guard var account = activeAccount else { showAccount = true; return }
        do {
            let defaults = state.settings
            let memoryAvailability = MemoryAvailability.current()
            let recorder = try GameSessionRecorder(paths: paths, instance: stored, accountMode: account.kind.rawValue)
            sessionRecorder = recorder; logsSessionID = recorder.record.id
            requestedLogSessionID = recorder.record.id
            logs.removeAll(); lastGameExit = nil; crashReports = []; recordingErrorShown = false
            publishSession(recorder.record)
            let presentation = stored.resolvedLaunchSettings(defaults: defaults).presentation
            launchPresentations[recorder.record.id] = presentation
            if presentation.showLogs { showLogs = true }
            perform(Messages.AppAppModelLaunching.launchingInstance(stored.name), presentErrors: false) { [self] id in
                journal.linkSession(recorder.record.id, to: id)
                do {
                    var instance = try stored.launchSnapshot(defaults: defaults, availability: memoryAvailability)
                    try Task.checkCancellation()
                    if !instance.installed {
                        try advanceSession(.installation)
                        let installed = try await installer.install(stored, concurrency: state.settings.concurrentDownloads) { [weak self] p in await self?.progress(id, p) }
                        try recordInstallation(installed, requested: stored)
                        instance = try installed.launchSnapshot(defaults: defaults, availability: memoryAvailability)
                    }
                    try advanceSession(.recovery)
                    try await ContentManager(paths: paths, instanceID: instance.id).recover()
                    try await WorldManager(paths: paths, instanceID: instance.id).recover()
                    try advanceSession(.account)
                    progress(id, InstallProgress(Messages.AppAppModelLaunching.checkingAccountAndJava))
                    var token = "0"
                    var externalAuth: ExternalAuthLaunch?
                    var offlineSkin: OfflineSkinLaunch?
                    try await accountOperations.withLock(for: account.id) {
                        if account.kind == .microsoft {
                            var credentials = try CredentialStore.load(for: account.id)
                            recorder.addSecrets([credentials.accessToken, credentials.refreshToken])
                            if credentials.expiresAt < Date().addingTimeInterval(120) {
                                (account, credentials) = try await MicrosoftAuth(clientID: credentials.clientID).refresh(credentials, account: account)
                                recorder.addSecrets([credentials.accessToken, credentials.refreshToken])
                                try addMicrosoft(account, credentials: credentials, activate: false, requireExisting: true)
                            }
                            token = credentials.accessToken
                        } else if account.kind == .external {
                            var credentials = try CredentialStore.loadExternal(for: account.id)
                            recorder.addSecrets([credentials.accessToken, credentials.clientToken])
                            (account, credentials) = try await ExternalAuthentication().refresh(account: account, credentials: credentials)
                            recorder.addSecrets([credentials.accessToken, credentials.clientToken])
                            try addExternal(account, credentials: credentials, requireExisting: true, activate: false)
                            guard let server = account.externalLogin?.server else { throw RuriError.message(Messages.AppAppModelLaunching.externalAuthRequired) }
                            progress(id, InstallProgress(Messages.AppAppModelLaunching.preparingAuthComponent))
                            async let metadata = ExternalAuthentication().metadata(for: server)
                            async let jar = AuthlibInjector().prepare(paths: paths)
                            externalAuth = try await ExternalAuthLaunch(jar: jar, metadata: metadata, userProperties: credentials.user?.propertiesJSON ?? "{}")
                            token = credentials.accessToken
                        }
                    }
                    let savedSkin = account.kind == .offline ? try SkinLibrary(paths: paths).preview(for: account.id) : nil
                    let savedCape = account.kind == .offline ? try SkinLibrary(paths: paths).cape(for: account.id) : nil
                    if savedSkin != nil || savedCape != nil {
                        progress(id, InstallProgress(Messages.OfflineSkin.preparing))
                        let jar = try await AuthlibInjector().prepare(paths: paths)
                        offlineSkin = try OfflineSkinLaunch(account: account, skin: savedSkin, cape: savedCape, injector: jar)
                        token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                    }
                    try advanceSession(.manifest)
                    let manifest = try await installer.loadManifest(instance)
                    if world != nil { try WorldQuickPlay.requireSupport(instance: instance, manifest: manifest) }
                    try advanceSession(.java)
                    let java = try await javaForLaunch(instance: instance, manifest: manifest, activityID: id)
                    try Task.checkCancellation()
                    try recorder.setJava(java.label + " · " + java.version)
                    try advanceSession(.arguments)
                    try await installer.prepareRunDirectory(instance, manifest: manifest)
                    let plan = try LaunchBuilder.build(instance: instance, manifest: manifest, java: java, account: account, accessToken: token, paths: paths, world: world, externalAuth: externalAuth, offlineSkin: offlineSkin)
                    recorder.addSecrets(plan.environmentRedactions)
                    if let world {
                        appendLog(Messages.AppAppModelLaunching.worldLaunch(world.name).localized)
                        // History metadata; a failure here must not stop a launch.
                        try? recorder.setWorld(.init(folder: world.folder, name: world.name, lastPlayed: world.lastPlayed, source: .quickPlay))
                    }
                    appendLog("[Ruri] \(java.label)")
                    appendLog("[Ruri] \(plan.redactedCommand)")
                    try advanceSession(.starting)
                    try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [token])
                    sessionRecorder = nil
                    activeSessions[instance.id] = recorder.record
                    try? GameMonitorClient.recordEvent(.connected, paths: paths, session: recorder.record)
                    publishSession(recorder.record)
                } catch {
                    finishLaunchPresentation(recorder.record.id)
                    let cancelled = Task.isCancelled || error is CancellationError
                    if !recorder.hasHandedOff {
                        do { try recorder.fail(error, cancelled: cancelled) } catch { showRecordingError(error) }
                    }
                    publishSession(recorder.record)
                    if let failure = recorder.record.failure { appendDisplayedLog("[Ruri] \(failure)") }
                    sessionRecorder = nil
                    if cancelled { throw CancellationError() }
                    showLogs = true; report(Messages.AppAppModelLaunching.launchFailureNotice(recorder.record.title), level: .error, sessionID: recorder.record.id)
                    throw RuriError.message(recorder.redacted(error.localizedDescription))
                }
            }
        } catch { self.error = error.localizedDescription }
    }
    private func advanceSession(_ stage: GameSession.Stage) throws {
        try sessionRecorder?.transition(stage)
        appendDisplayedLog("[Ruri] \(stage.title)")
        if let record = sessionRecorder?.record { publishSession(record) }
    }
    private func showRecordingError(_ error: any Error) {
        guard !recordingErrorShown else { return }
        recordingErrorShown = true
        let message = Messages.AppAppModelLaunching.runRecordIncomplete(String(describing: sessionRecorder?.redacted(error.localizedDescription) ?? error.localizedDescription)).localized
        report(message, level: .warning, sessionID: sessionRecorder?.record.id); appendDisplayedLog("[Ruri] \(message)")
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
}
