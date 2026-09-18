import SwiftUI
import RuriCore
import RuriLocalization

extension GameSession {
    var userResult: String {
        if hasPostCommandFailure { return Messages.SessionUI.afterCommandFailed.localized }
        switch state {
        case .preparing: return Messages.SessionUI.preparing.localized
        case .running:
            if exit != nil { return Messages.SessionUI.checking.localized }
            if monitorIdentity?.liveness == .exited { return Messages.SessionUI.interrupted.localized }
            return Messages.SessionUI.running.localized
        case .succeeded: return Messages.SessionUI.finished.localized
        case .stopped: return Messages.SessionUI.stopped.localized
        case .failed: return exit == nil ? Messages.SessionUI.launchFailed.localized : Messages.SessionUI.crashed.localized
        case .cancelled: return Messages.SessionUI.cancelled.localized
        case .interrupted: return Messages.SessionUI.interrupted.localized
        }
    }
    var overviewHelp: String {
        if hasPostCommandFailure { return Messages.SessionUI.afterCommandHelp.localized }
        if state == .interrupted || (!state.isFinished && monitorIdentity?.liveness == .exited) { return Messages.SessionUI.interruptedHelp.localized }
        if exit != nil && !state.isFinished { return Messages.SessionUI.finishingHelp.localized }
        if !state.isFinished { return Messages.SessionUI.runningHelp.localized }
        return needsAttention ? Messages.SessionUI.failureHelp.localized : Messages.SessionUI.normalHelp.localized
    }
    var resultSymbol: String {
        if hasPostCommandFailure { return "exclamationmark.triangle" }
        switch state {
        case .preparing, .running: return exit == nil ? "gamecontroller" : "checkmark.circle"
        case .succeeded: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .interrupted: return "questionmark.circle"
        case .stopped, .cancelled: return "stop.circle"
        }
    }
    var resultColor: Color {
        if needsAttention { return .orange }
        return state == .running || state == .preparing ? .accentColor : .secondary
    }
    /// When the run began, preferring the measured clock over the record's own
    /// creation stamp so a slow launch is not counted as play time.
    var startDate: Date { timing?.startedAt ?? exit?.startedAt ?? createdAt }
    var endDate: Date? {
        if let exit { return exit.endedAt }
        guard let timing, state.isFinished else { return nil }
        return timing.observedAt
    }
    var userDuration: String {
        guard hasPlayed else { return Messages.SessionUI.notStarted.localized }
        if exit == nil && timing == nil { return Messages.SessionUI.unknownTime.localized }
        let value = LocalizedFormat.duration(playedSeconds)
        if timing?.quality == .interrupted || (exit == nil && monitorIdentity?.liveness == .exited) { return Messages.SessionUI.partialTime(value).localized }
        return value
    }
}
