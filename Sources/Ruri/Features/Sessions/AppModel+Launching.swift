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
        guard let account = activeAccount else { showAccount = true; return }
        do {
            let recorder = try GameSessionRecorder(paths: paths, instance: stored, accountMode: account.kind.rawValue)
            sessionRecorder = recorder; logsSessionID = recorder.record.id
            requestedLogSessionID = recorder.record.id
            logs.removeAll(); lastGameExit = nil; crashReports = []; recordingErrorShown = false
            publishSession(recorder.record)
            let presentation = stored.resolvedLaunchSettings(defaults: state.settings).presentation
            launchPresentations[recorder.record.id] = presentation
            if presentation.showLogs { showLogs = true }
            perform(Messages.AppAppModelLaunching.launchingInstance(stored.name), presentErrors: false) { [self] id in
                journal.linkSession(recorder.record.id, to: id)
                do {
                    let record = try await LaunchService(paths: paths, downloader: downloader).start(
                        instanceID: stored.id, accountID: account.id, worldFolder: world?.folder, recorder: recorder,
                        javaResolver: { [self] instance, manifest in try await javaForLaunch(instance: instance, manifest: manifest, activityID: id) },
                        progress: { [weak self] p in await self?.progress(id, p) },
                        updated: { [self] record in publishSession(record) })
                    acceptState(try StateStore.load(basePaths))
                    sessionRecorder = nil
                    activeSessions[stored.id] = record
                    try? GameMonitorClient.recordEvent(.connected, paths: paths, session: record)
                    publishSession(record)
                } catch {
                    finishLaunchPresentation(recorder.record.id)
                    publishSession(recorder.record)
                    if let failure = recorder.record.failure { appendDisplayedLog("[Ruri] \(failure)") }
                    sessionRecorder = nil
                    if error is CancellationError || Task.isCancelled { throw CancellationError() }
                    showLogs = true; report(Messages.AppAppModelLaunching.launchFailureNotice(recorder.record.title), level: .error, sessionID: recorder.record.id)
                    throw error
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
