import SwiftUI
import RuriCore
import RuriLocalization

struct LauncherNotificationButton: View {
    @Environment(AppModel.self) private var model
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            Label(Messages.LauncherLog.notifications.localized, systemImage: model.journal.unreadCount > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.hierarchical)
        }
        .help(model.journal.unreadCount > 0 ? Messages.LauncherLog.unreadCount(Int64(model.journal.unreadCount)).localized : Messages.LauncherLog.notifications.localized)
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
                                model.showLauncherLog(entry.id)
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
