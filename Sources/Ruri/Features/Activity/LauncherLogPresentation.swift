import AppKit
import SwiftUI
import RuriCore
import RuriLocalization

extension LauncherLogEntry.Kind {
    var title: String {
        switch self {
        case .launcher: Messages.LauncherLog.launcher.localized
        case .task: Messages.LauncherLog.task.localized
        case .game: Messages.LauncherLog.game.localized
        }
    }
}

extension LauncherLogEntry {
    /// Older launch entries used the initial stage as their final summary.
    var summary: String? {
        if status == .completed, detailMessage == Messages.AppActivityItem.preparing { return nil }
        return detail
    }
    var statusTitle: String {
        switch status {
        case .running: Messages.LauncherLog.running.localized
        case .completed: needsAttention ? levelTitle : Messages.LauncherLog.completed.localized
        case .failed: Messages.LauncherLog.failed.localized
        case .cancelled: Messages.LauncherLog.cancelled.localized
        case .interrupted: Messages.LauncherLog.interrupted.localized
        case .recorded: levelTitle
        }
    }
    var levelTitle: String {
        switch level {
        case .info: Messages.LauncherLog.info.localized
        case .success: Messages.LauncherLog.success.localized
        case .warning: Messages.LauncherLog.warning.localized
        case .error: Messages.LauncherLog.error.localized
        }
    }
    var symbol: String {
        if status == .running { return "circle.dotted" }
        if status == .cancelled { return "minus.circle" }
        switch level {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
    var tint: Color {
        if status == .running { return .accentColor }
        switch level {
        case .info: return .secondary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
    var plainText: String {
        let date = ISO8601DateFormatter()
        var lines = ["\(date.string(from: startedAt)) [\(kind.title)] [\(statusTitle)] \(title)"]
        if let detail { lines.append(detail) }
        lines += steps.map { "\(date.string(from: $0.date))  \($0.message.localized)" }
        if let sessionID { lines.append(sessionID.uuidString) }
        if let fileURL { lines.append(fileURL.path) }
        return lines.joined(separator: "\n")
    }
    func matches(_ query: String) -> Bool {
        query.isEmpty || [title, detail ?? "", kind.title, statusTitle, progress.stage]
            .contains { $0.localizedStandardContains(query) }
            || steps.contains { $0.message.localized.localizedStandardContains(query) }
    }
}

struct LauncherEntrySymbol: View {
    let entry: LauncherLogEntry
    var body: some View {
        Image(systemName: entry.symbol).foregroundStyle(entry.tint)
            .font(.system(size: 15)).frame(width: 20)
            .accessibilityLabel(entry.statusTitle)
    }
}

struct LauncherEntryActions: View {
    @Environment(AppModel.self) private var model
    let entry: LauncherLogEntry
    var body: some View {
        if entry.status == .running {
            Button(Messages.LauncherLog.cancelTask.localized) { model.operation?.cancel() }
                .disabled(model.activeActivity?.id != entry.id)
        }
        if let id = entry.sessionID {
            Button(Messages.AppRootView.viewRecord.localized) { model.showSession(id) }
        }
        if let url = entry.fileURL {
            Button(Messages.AppRootView.showInFinder.localized) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(GameShareRedactor().redact(entry.plainText), forType: .string)
        } label: { Label(Messages.LauncherLog.copy.localized, systemImage: "doc.on.doc") }
            .help(Messages.LauncherLog.copy.localized)
    }
}
