import RuriLocalization
import SwiftUI
import RuriCore

/// Display strings and colours shared by the home page and the library so
/// both describe an instance the same way.
extension AppModel {
    func statusLabel(_ instance: GameInstance) -> String {
        runningLabel(instance.id) ?? (instance.repositoryIssue != nil ? Messages.AppInstancePresentation.statusLabelText1.localized : instance.installed ? Messages.AppInstancePresentation.statusLabelText2.localized : Messages.AppInstancePresentation.statusLabelText3.localized)
    }
    func statusIsNominal(_ instance: GameInstance) -> Bool {
        runningLabel(instance.id) == nil && instance.repositoryIssue == nil && instance.installed
    }
    /// Semantic status colour: green when ready, blue while a game or task
    /// is live, orange for anything waiting on the player, red for damage.
    func statusColor(_ instance: GameInstance) -> Color {
        if instance.repositoryIssue != nil { return .red }
        if activeSessions[instance.id] != nil { return .blue }
        if runningLabel(instance.id) != nil || !instance.installed { return .orange }
        return .green
    }
    func memoryLabel(_ instance: GameInstance) -> String {
        guard let memory = try? instance.resolvedLaunchSettings(defaults: state.settings).memoryPreview() else { return Messages.AppInstancePresentation.memoryText1.localized }
        return "\(memory.maximumMB) MB" + (memory.maximumSource == .automatic ? Messages.AppInstancePresentation.memoryText2.localized : memory.maximumSource == .jvmArguments ? Messages.AppInstancePresentation.memoryText3.localized : "")
    }
}

extension GameInstance {
    var lastPlayedLabel: String { lastPlayed.map { Messages.AppInstancePresentation.lastPlayed(LocalizedFormat.relative($0)).localized } ?? Messages.AppInstancePresentation.lastPlayedLabelText2.localized }
    var playTimeLabel: String {
        guard playTime >= 60 else { return playTime > 0 ? Messages.AppInstancePresentation.playTimeLabelText1.localized : Messages.AppInstancePresentation.lastPlayedLabelText2.localized }
        return LocalizedFormat.duration(playTime)
    }
    var loaderLabel: String { loader == .vanilla ? Messages.AppInstancePresentation.loaderLabelText1.localized : loader.title + (loaderVersion.map { " " + $0 } ?? "") }
}
