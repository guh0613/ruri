import RuriLocalization
import SwiftUI
import RuriCore

/// Normal availability is implicit in the launch action. Callers can reserve
/// the hidden line's space to keep surrounding content stable as status changes.
struct InstanceStatus: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var reservesSpace = false
    private var isNominal: Bool { model.statusIsNominal(instance) }
    var body: some View {
        if reservesSpace || !isNominal {
            Label(model.statusLabel(instance), systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(model.statusColor(instance))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(isNominal ? 0 : 1)
                .accessibilityHidden(isNominal)
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
    /// The heap a launch would give, collector included, as settings show it.
    func plannedMemory(_ instance: GameInstance) -> LaunchMemory? {
        try? JVMPlan.preview(settings: instance.resolvedLaunchSettings(defaults: state.settings), workload: MemoryWorkload.cached(paths: paths, instance: instance),
                             context: runtimeContexts[instance.id]).memory
    }
    /// Everything the context depends on; the manifest cache checks its files itself.
    func runtimeContextKey(_ instance: GameInstance) -> String {
        "\(instance.id)|\(instance.resolvedLaunchSettings(defaults: state.settings).java)|\(instance.installed)|\(instance.loaderVersion ?? "")|\(instance.repositoryVersionID ?? "")|\(runtimes.map(\.path))"
    }
    func refreshRuntimeContext(_ instance: GameInstance) async {
        let context = await JVMRuntimeContext.preview(instance: instance, java: instance.resolvedLaunchSettings(defaults: state.settings).java, paths: paths, runtimes: runtimes)
        if !Task.isCancelled, runtimeContexts[instance.id] != context { runtimeContexts[instance.id] = context }
    }
    func memoryLabel(_ instance: GameInstance) -> String {
        guard let memory = plannedMemory(instance) else { return Messages.AppInstancePresentation.memoryNeedsCheck.localized }
        return "\(memory.maximumMB) MB" + (memory.maximumSource == .automatic ? Messages.AppInstancePresentation.automaticMemory.localized : memory.maximumSource == .jvmArguments ? Messages.AppInstancePresentation.memoryArguments.localized : "")
    }
}

extension GameInstance {
    var lastPlayedLabel: String { lastPlayed.map { Messages.AppInstancePresentation.lastPlayed(LocalizedFormat.relative($0)).localized } ?? Messages.AppInstancePresentation.neverPlayed.localized }
    var playTimeLabel: String {
        guard playTime >= 60 else { return playTime > 0 ? Messages.AppInstancePresentation.lessThanAMinute.localized : Messages.AppInstancePresentation.neverPlayed.localized }
        return LocalizedFormat.duration(playTime)
    }
    var loaderLabel: String { loaderSummary }
}
