import SwiftUI
import RuriCore
import RuriLocalization

struct LauncherNotificationButton: View {
    @Environment(AppModel.self) private var model
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            // A running task takes the bell's place, like a download in Safari.
            if let task = model.activeActivity {
                Label { Text(task.title) } icon: { LauncherTaskProgress(entry: task).controlSize(.small) }
            } else {
                Label(Messages.LauncherLog.notifications.localized, systemImage: model.journal.unreadCount > 0 ? "bell.badge" : "bell")
                    .symbolRenderingMode(.hierarchical)
            }
        }
        .help(model.activeActivity?.title ?? (model.journal.unreadCount > 0 ? Messages.LauncherLog.unreadCount(Int64(model.journal.unreadCount)).localized : Messages.LauncherLog.notifications.localized))
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            LauncherNotificationInbox(presented: $presented)
        }
    }
}

private struct LauncherNotificationInbox: View {
    @Environment(AppModel.self) private var model
    @Binding var presented: Bool
    @State private var unreadOnly = false
    private var entries: [LauncherLogEntry] { model.journal.notifications.filter { !unreadOnly || !$0.isRead } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Messages.LauncherLog.notifications.localized).font(.headline)
                Spacer()
                Button(Messages.LauncherLog.markAllRead.localized) { model.markLogRead() }
                    .buttonStyle(.link).font(.caption).disabled(model.journal.unreadCount == 0)
            }.padding(16)
            if let task = model.activeActivity {
                LauncherRunningTaskCard(entry: task) { model.openLogEntry(task); presented = false }
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
            Picker(Messages.LauncherLog.notifications.localized, selection: $unreadOnly) {
                Text(Messages.LauncherLog.all.localized).tag(false)
                Text(Messages.LauncherLog.unread.localized).tag(true)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            ScrollView {
                if entries.isEmpty {
                    ContentUnavailableView(Messages.LauncherLog.noNotifications.localized, systemImage: "bell",
                                           description: Text(Messages.LauncherLog.notificationHint.localized)).frame(minHeight: 220)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Button {
                                model.openLogEntry(entry)
                                presented = false
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    LauncherEntrySymbol(entry: entry).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(entry.title).font(.callout.weight(entry.isRead ? .regular : .semibold)).foregroundStyle(.primary).lineLimit(2)
                                            Spacer(minLength: 0)
                                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                                .opacity(entry.isRead ? 0 : 1)
                                                .accessibilityHidden(entry.isRead)
                                                .accessibilityLabel(Messages.LauncherLog.unread.localized)
                                        }
                                        if let detail = entry.summary { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                                        HStack(alignment: .firstTextBaseline) {
                                            Text(entry.statusTitle)
                                            Spacer()
                                            Text(entry.updatedAt, format: .dateTime.month().day().hour().minute()).monospacedDigit().fixedSize()
                                        }.font(.caption2).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Divider().padding(.leading, 46)
                        }
                    }
                }
            }.frame(height: 340)
            Divider()
            Button(Messages.LauncherLog.showAll.localized) { model.showLauncherLog(); presented = false }
                .buttonStyle(.link).padding(14)
        }.frame(width: 380)
    }
}

/// The task in progress, pinned above the notifications with its live stages.
private struct LauncherRunningTaskCard: View {
    @Environment(AppModel.self) private var model
    let entry: LauncherLogEntry
    let open: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.title).font(.callout.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Button { model.operation?.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(Messages.LauncherLog.cancelTask.localized)
                    .accessibilityLabel(Messages.LauncherLog.cancelTask.localized)
            }
            // The main stage first, then work running alongside it.
            ForEach(Array(([entry.progress] + entry.parallelProgress).enumerated()), id: \.offset) { _, progress in
                VStack(alignment: .leading, spacing: 4) {
                    if progress.total > 0 { ProgressView(value: min(1, progress.fraction)) }
                    else { ProgressView().progressViewStyle(.linear) }
                    HStack(alignment: .firstTextBaseline) {
                        Text(progress.stage).lineLimit(1)
                        Spacer(minLength: 8)
                        if progress.total > 0 {
                            Text(Messages.LauncherLog.transferProgress(Int64(progress.completed), Int64(progress.total)).localized)
                                .monospacedDigit().fixedSize()
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: open)
    }
}
