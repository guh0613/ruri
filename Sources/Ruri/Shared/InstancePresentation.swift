import RuriLocalization
import SwiftUI
import RuriCore

/// Normal availability is implicit in the launch action. Reserve a status
/// line for work in progress or something that needs the player's attention.
struct InstanceStatus: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var body: some View {
        if !model.statusIsNominal(instance) {
            Label(model.statusLabel(instance), systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(model.statusColor(instance))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var symbol: String {
        if instance.repositoryIssue != nil || model.customDirectoryErrors[instance.id] != nil || model.directoryErrors[model.paths.directoryID(for: instance.id)] != nil {
            return "exclamationmark.triangle"
        }
        if model.activeSessions[instance.id] != nil { return "play.circle" }
        if !instance.installed { return "arrow.down.circle" }
        return "clock.arrow.circlepath"
    }
}

/// Display strings and colours shared by the home page and the library so
/// both describe an instance the same way.
extension AppModel {
    func statusLabel(_ instance: GameInstance) -> String {
        runningLabel(instance.id) ?? (instance.repositoryIssue != nil ? Messages.AppInstancePresentation.needsCheck.localized : instance.installed ? Messages.AppInstancePresentation.ready.localized : Messages.AppInstancePresentation.pendingInstall.localized)
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
        guard let memory = try? instance.resolvedLaunchSettings(defaults: state.settings).memoryPreview() else { return Messages.AppInstancePresentation.memoryNeedsCheck.localized }
        return "\(memory.maximumMB) MB" + (memory.maximumSource == .automatic ? Messages.AppInstancePresentation.automaticMemory.localized : memory.maximumSource == .jvmArguments ? Messages.AppInstancePresentation.memoryArguments.localized : "")
    }
}

extension GameInstance {
    var lastPlayedLabel: String { lastPlayed.map { Messages.AppInstancePresentation.lastPlayed(LocalizedFormat.relative($0)).localized } ?? Messages.AppInstancePresentation.neverPlayed.localized }
    var playTimeLabel: String {
        guard playTime >= 60 else { return playTime > 0 ? Messages.AppInstancePresentation.lessThanAMinute.localized : Messages.AppInstancePresentation.neverPlayed.localized }
        return LocalizedFormat.duration(playTime)
    }
    var loaderLabel: String { loader == .vanilla ? Messages.AppInstancePresentation.vanilla.localized : loader.title + (loaderVersion.map { " " + $0 } ?? "") }
}
