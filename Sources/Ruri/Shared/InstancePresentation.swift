import SwiftUI
import RuriCore

/// Display strings and colours shared by the home page and the library so
/// both describe an instance the same way.
extension AppModel {
    func statusLabel(_ instance: GameInstance) -> String {
        runningLabel(instance.id) ?? (instance.repositoryIssue != nil ? "需要检查" : instance.installed ? "就绪" : "待安装")
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
        guard let memory = try? instance.resolvedLaunchSettings(defaults: state.settings).memoryPreview() else { return "内存设置待检查" }
        return "\(memory.maximumMB) MB" + (memory.maximumSource == .automatic ? " · 自动" : memory.maximumSource == .jvmArguments ? " · 参数" : "")
    }
}

extension GameInstance {
    var lastPlayedLabel: String { lastPlayed.map { "上次游玩 " + $0.formatted(.relative(presentation: .named)) } ?? "尚未游玩" }
    var playTimeLabel: String {
        guard playTime >= 60 else { return playTime > 0 ? "不到 1 分钟" : "尚未游玩" }
        return Duration.seconds(playTime).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
    var loaderLabel: String { loader == .vanilla ? "原版" : loader.title + (loaderVersion.map { " " + $0 } ?? "") }
}
