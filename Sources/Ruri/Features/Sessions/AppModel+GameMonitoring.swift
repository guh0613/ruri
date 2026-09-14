import RuriLocalization
import Foundation
import AppKit
import RuriCore

extension AppModel {
    func isInstanceInUse(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return activeSessions[id] != nil || pendingDirectoryCopyIDs.contains(id) || GameRunLease.isHeld(paths: paths, instanceID: id)
    }
    func runningLabel(_ id: UUID) -> String? {
        if pendingInstanceMoveIDs.contains(id) || InstanceMoveGuard.hasPending(paths: paths, instanceID: id) { return Messages.AppAppModelGameMonitoring.pendingMove.localized }
        if pendingInstanceCopyIDs.contains(id) || InstanceCopyGuard.hasPending(paths: paths, instanceID: id) { return Messages.AppAppModelGameMonitoring.pendingCopy.localized }
        if pendingDirectoryCopyIDs.contains(id) || RunDirectoryCopyGuard.hasPending(paths: paths, instanceID: id) { return Messages.AppAppModelGameMonitoring.pendingDirectoryCopy.localized }
        guard let record = activeSessions[id] else {
            if customDirectoryErrors[id] != nil { return Messages.AppAppModelGameMonitoring.inaccessibleGameDirectory.localized }
            return directoryErrors[paths.directoryID(for: id)] == nil ? nil : Messages.AppAppModelGameMonitoring.inaccessibleFolder.localized
        }
        switch GameMonitorClient.activity(record) {
        case .orphaned: return Messages.AppAppModelGameMonitoring.monitoringDisconnected.localized
        case .uncertain: return Messages.AppAppModelGameMonitoring.statusNeedsConfirmation.localized
        case .inactive: return nil
        case .monitoring:
            if record.state.isFinished { return Messages.AppAppModelGameMonitoring.savingRecord.localized }
            if record.stage == .quitting { return Messages.AppAppModelGameMonitoring.waitingForExit.localized }
            if record.stage == .beforeCommand || record.stage == .afterCommand { return record.stage.title }
            if record.stage == .stopping { return Messages.AppAppModelGameMonitoring.terminatingProcess.localized }
            return record.gameIdentity == nil ? Messages.AppAppModelGameMonitoring.launching.localized : Messages.AppAppModelGameMonitoring.running.localized
        }
    }
    func returnToGame(_ id: UUID) {
        guard let record = activeSessions[id] ?? sessions.first(where: { $0.instanceID == id && !$0.state.isFinished && $0.gameIdentity?.isAlive == true }) else { return }
        guard let identity = record.gameIdentity, identity.isAlive,
              let application = NSRunningApplication(processIdentifier: identity.pid), !application.isTerminated else {
            showSession(record.id); return
        }
        if application.activate(options: [.activateAllWindows]) { try? GameMonitorClient.recordEvent(.gameActivationRequested, paths: paths, session: record) }
        else { report(Messages.AppAppModelGameMonitoring.gameWindowUnavailable, level: .warning) }
    }
    func requestGameQuit(_ instanceID: UUID) {
        guard let record = activeSessions[instanceID] else { return }
        do {
            try GameMonitorClient.requestNormalQuit(paths: paths, record: record)
            report(Messages.AppAppModelGameMonitoring.normalExitRequested, sessionID: record.id)
        } catch { report(error.localizedDescription, level: .error, sessionID: record.id) }
    }
    func confirmGameTermination(_ instanceID: UUID) {
        guard let record = activeSessions[instanceID], !record.state.isFinished, record.monitorIdentity?.isAlive == true else { return }
        if record.stage == .beforeCommand || record.stage == .afterCommand {
            do { try GameMonitorClient.requestStop(paths: paths, record: record) }
            catch { report(error.localizedDescription, level: .error, sessionID: record.id) }
            return
        }
        let alert = NSAlert()
        alert.messageText = Messages.AppAppModelGameMonitoring.terminateGameProcess(record.instanceName).localized
        alert.informativeText = Messages.AppAppModelGameMonitoring.terminateWarning.localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: Messages.Common.cancel.localized)
        alert.addButton(withTitle: Messages.AppAppModelGameMonitoring.terminateProcess.localized)
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do { try GameMonitorClient.requestStop(paths: paths, record: record) }
        catch { report(error.localizedDescription, level: .error, sessionID: record.id) }
    }
    func didRecoverSession(_ record: GameSession) async {
        publishSession(record)
        finishLaunchPresentation(record.id)
        if activeSessions[record.instanceID]?.id == record.id { activeSessions.removeValue(forKey: record.instanceID) }
        handledExits.insert(record.id)
        acknowledgeSession(record)
        report(record.title, sessionID: record.id)
    }
    func showSession(_ id: UUID? = nil) {
        requestedLogSessionID = id ?? logsSessionID ?? sessions.first?.id
        openMainWindow?(); showLogs = true
    }
    func acknowledgeSession(_ record: GameSession) {
        do {
            try GameSessionReviewStore.mark(record, paths: paths)
            NSApp.dockTile.badgeLabel = sessions.contains(where: needsReview) ? "!" : nil
        } catch { report(Messages.AppAppModelGameMonitoring.acknowledgeSessionFailure(error.localizedDescription), level: .error) }
    }
    private func reviewed(_ record: GameSession) -> Bool {
        (try? GameSessionReviewStore.contains(record, paths: paths)) ?? false
    }
    private func needsReview(_ record: GameSession) -> Bool {
        guard record.monitorIdentity != nil else { return false }
        let attention = record.state == .failed || record.commandResults?.contains(where: { !$0.succeeded && !$0.cancelled }) == true || (!record.state.isFinished && GameMonitorClient.activity(record) != .monitoring)
        return attention && !reviewed(record)
    }
    func recordClientEvent(_ event: GameMonitorClient.ClientEvent) {
        for record in activeSessions.values { try? GameMonitorClient.recordEvent(event, paths: paths, session: record) }
    }
    func startGameObservation() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let watchedSessions = Set(activeSessions.values.map(\.id)), watchedInstances = state.instances.map(\.id)
                let directories = [paths.root] + state.instances.flatMap {
                    [paths.instance($0.id), paths.instance($0.id).appendingPathComponent("sessions")]
                } + activeSessions.values.compactMap { try? GameSessionStore.directory(paths: paths, instanceID: $0.instanceID, sessionID: $0.id) }
                let observer = FileChangeObserver(directories: directories, processes: activeSessions.values.compactMap { $0.monitorIdentity?.pid })
                // Re-arm before reading so writes during refresh queue a wakeup.
                await refreshSessions(useCache: true)
                await pollGames()
                if watchedSessions != Set(activeSessions.values.map(\.id)) || watchedInstances != state.instances.map(\.id) { observer.cancel(); continue }
                for await _ in observer.events {
                    break
                }
                observer.cancel()
            }
        }
    }
    func pollGames() async {
        let previous = activeSessions
        let snapshot = sessions, snapshotIDs = Set(sessions.map(\.id))
        var active: [UUID: GameSession] = [:]
        var presentedAttention = false
        for record in snapshot where record.monitorIdentity != nil && (!record.state.isFinished || previous[record.instanceID]?.id == record.id || (!handledExits.contains(record.id) && (record.state == .failed || record.commandResults?.contains(where: { !$0.succeeded && !$0.cancelled }) == true))) {
            let activity = GameMonitorClient.activity(record)
            if activity == .inactive || record.state.isFinished || record.exit != nil { finishLaunchPresentation(record.id) }
            else { applyLaunchPresentation(record) }
            if activity != .inactive {
                if previous[record.instanceID]?.id != record.id { try? GameMonitorClient.recordEvent(.connected, paths: paths, session: record) }
                if active[record.instanceID] == nil { active[record.instanceID] = record }
                if logsSessionID == nil { logsSessionID = record.id }
            } else if previous[record.instanceID]?.id == record.id {
                if let exit = record.exit { lastGameExit = exit }
                if !needsReview(record) { report(record.title, level: .success, sessionID: record.id) }
            }
            if needsReview(record) && !handledExits.contains(record.id) {
                handledExits.insert(record.id)
                NSApp.dockTile.badgeLabel = "!"
                let summary = activity == .orphaned ? Messages.AppAppModelGameMonitoring.monitoringStopped.localized : activity == .uncertain ? Messages.AppAppModelGameMonitoring.statusUnconfirmed.localized : record.title
                report("\(record.instanceName)：\(summary)", level: record.state == .failed ? .error : .warning, sessionID: record.id)
                if !presentedAttention {
                    if NSApp.isActive && NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
                        requestedLogSessionID = record.id; showLogs = true
                    }
                    presentedAttention = true
                }
            }
        }
        for (id, record) in activeSessions where !snapshotIDs.contains(record.id) { active[id] = record }
        // A recovery action may have completed while a log read yielded above.
        // Do not restore that action's older active snapshot into the UI.
        for (id, record) in active {
            if let latest = sessions.first(where: { $0.id == record.id }), latest != record {
                if GameMonitorClient.activity(latest) == .inactive { active.removeValue(forKey: id) }
                else { active[id] = latest }
            }
        }
        if activeSessions != active { activeSessions = active }
        await restorePlaytime()
    }
    private func applyLaunchPresentation(_ record: GameSession) {
        guard let presentation = launchPresentations[record.id], record.gameIdentity?.isAlive == true else { return }
        if record.host?.backend == .native && record.host?.windowReadyAt == nil { return }
        launchPresentations.removeValue(forKey: record.id)
        guard presentation.hideLauncher, !presentation.showLogs, !showLogs else { return }
        if !NSApp.isHidden {
            automaticallyHiddenSessions.insert(record.id)
            NSApp.hide(nil)
        } else if !automaticallyHiddenSessions.isEmpty {
            automaticallyHiddenSessions.insert(record.id)
        }
    }
    func finishLaunchPresentation(_ sessionID: UUID) {
        launchPresentations.removeValue(forKey: sessionID)
        guard automaticallyHiddenSessions.remove(sessionID) != nil, automaticallyHiddenSessions.isEmpty, NSApp.isHidden else { return }
        NSApp.unhide(nil)
        openMainWindow?()
    }
    private func restorePlaytime() async {
        var changed = false
        let paths = paths
        for id in state.instances.map(\.id) {
            let completed = Set(sessions.filter { $0.instanceID == id && $0.state.isFinished && $0.exit != nil }.map(\.id))
            guard restoredPlaytimeSessions[id] != completed else { continue }
            let ledger = await Task.detached(priority: .utility) { try? GamePlaytimeStore.load(paths: paths, instanceID: id) }.value
            guard let index = state.instances.firstIndex(where: { $0.id == id }) else { continue }
            restoredPlaytimeSessions[id] = completed
            if let ledger {
                if state.instances[index].playTime != ledger.total { state.instances[index].playTime = ledger.total; changed = true }
                if (state.instances[index].lastPlayed ?? .distantPast) < ledger.lastPlayed { state.instances[index].lastPlayed = ledger.lastPlayed; changed = true }
            }
        }
        if changed { save() }
    }
    func prepareToQuit() async {
        isQuitting = true
        bootTask?.cancel()
        operation?.cancel()
        await operation?.value
        monitorTask?.cancel()
        await journalWriteTask?.value
    }
}
