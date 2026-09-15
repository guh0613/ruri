import SwiftUI
import RuriCore
import RuriLocalization

struct LauncherLogView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all, tasks, attention, transfers
        var id: Self { self }
        var title: String {
            switch self {
            case .all: Messages.LauncherLog.all.localized
            case .tasks: Messages.LauncherLog.tasks.localized
            case .attention: Messages.LauncherLog.attention.localized
            case .transfers: Messages.LauncherLog.transfers.localized
            }
        }
    }
    @Environment(AppModel.self) private var model
    @State private var filter = Filter.all
    @State private var search = ""
    @State private var confirmClear = false
    private var entries: [LauncherLogEntry] {
        model.journal.entries.filter { entry in
            (filter != .tasks || entry.kind == .task) &&
            (filter != .attention || entry.needsAttention) && entry.matches(search.trimmingCharacters(in: .whitespaces))
        }.sorted {
            if ($0.status == .running) != ($1.status == .running) { return $0.status == .running }
            return $0.updatedAt > $1.updatedAt
        }
    }
    private var selection: LauncherLogEntry? { model.journal.entries.first { $0.id == model.selectedLogID } }
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Picker(Messages.LauncherLog.category.localized, selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(Messages.LauncherLog.search.localized, text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel(Messages.LauncherLog.clearSearch.localized)
                    }
                }.padding(6).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .frame(minWidth: 120, maxWidth: 220)
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if filter == .transfers {
                LauncherTransfersView(search: search)
            } else {
                VStack(spacing: 0) {
                    Table(entries, selection: $model.selectedLogID) {
                        TableColumn(Messages.LauncherLog.event.localized) { entry in
                            HStack(spacing: 10) {
                                LauncherEntrySymbol(entry: entry)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.title).fontWeight(entry.isNotification && !entry.isRead ? .semibold : .regular).lineLimit(1)
                                    if entry.status == .running {
                                        Text(entry.progress.stage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.padding(.vertical, 7)
                                if entry.isNotification && !entry.isRead {
                                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                                        .accessibilityLabel(Messages.LauncherLog.unread.localized)
                                }
                            }
                        }.width(min: 180, ideal: 340)
                        TableColumn(Messages.LauncherLog.status.localized) { entry in
                            if entry.status == .running {
                                HStack(spacing: 5) {
                                    ProgressView().controlSize(.mini)
                                    Text(entry.statusTitle).font(.caption)
                                }
                            } else { Text(entry.statusTitle).font(.caption).foregroundStyle(entry.needsAttention ? entry.tint : .secondary) }
                        }.width(80)
                        TableColumn(Messages.LauncherLog.time.localized) { entry in
                            Text(entry.updatedAt, format: .dateTime.month().day().hour().minute()).monospacedDigit().foregroundStyle(.secondary)
                                .help(entry.updatedAt.formatted(date: .abbreviated, time: .standard))
                        }.width(138)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: false))
                    .contextMenu(forSelectionType: UUID.self) { ids in
                        if let id = ids.first, let entry = model.journal.entries.first(where: { $0.id == id }) { LauncherEntryActions(entry: entry) }
                    }
                    .overlay {
                        if entries.isEmpty {
                            ContentUnavailableView {
                                Label(search.isEmpty ? (filter == .attention ? Messages.LauncherLog.noAttention.localized : Messages.LauncherLog.noEntries.localized) : Messages.LauncherLog.noMatches.localized,
                                      systemImage: filter == .attention ? "checkmark.circle" : "list.bullet.rectangle")
                            } description: {
                                Text(search.isEmpty ? (filter == .attention ? Messages.LauncherLog.noAttentionHint.localized : Messages.LauncherLog.emptyHint.localized) : Messages.LauncherLog.searchHint.localized)
                            }
                        }
                    }.frame(minHeight: 150, maxHeight: .infinity)
                    if let selection {
                        Divider()
                        LauncherLogDetail(entry: selection).id(selection.id)
                    }
                }
                Divider()
                HStack {
                    Text(Messages.LauncherLog.entryCount(Int64(entries.count)).localized)
                    Spacer()
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 9)
            }
            if let error = model.journalStorageError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
        }
        .background(.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(Messages.LauncherLog.markAllRead.localized) { model.markLogRead() }.disabled(model.journal.unreadCount == 0)
                    Button(Messages.LauncherLog.export.localized) { model.exportLauncherLog(entries) }.disabled(entries.isEmpty || filter == .transfers)
                    Divider()
                    Button(Messages.LauncherLog.clear.localized, role: .destructive) { confirmClear = true }
                        .disabled(!model.journal.entries.contains { $0.status != .running })
                } label: { Label(Messages.LauncherLog.title.localized, systemImage: "ellipsis.circle") }
            }
        }
        .confirmationDialog(Messages.LauncherLog.clearTitle.localized, isPresented: $confirmClear, titleVisibility: .visible) {
            Button(Messages.LauncherLog.clearConfirm.localized, role: .destructive) { model.clearLogHistory() }
        } message: { Text(Messages.LauncherLog.clearDetail.localized) }
        .onChange(of: model.selectedLogID) { _, id in
            if let id {
                if filter == .transfers || !entries.contains(where: { $0.id == id }) { filter = .all; search = "" }
                model.markLogRead(id)
            }
        }
        .onChange(of: filter) { _, _ in
            if filter == .transfers || !entries.contains(where: { $0.id == model.selectedLogID }) { model.selectedLogID = nil }
        }
        .onChange(of: selection?.isRead) { _, isRead in
            if isRead == false, let id = model.selectedLogID { model.markLogRead(id) }
        }
        .onChange(of: search) { _, _ in
            if !entries.contains(where: { $0.id == model.selectedLogID }) { model.selectedLogID = nil }
        }
    }
}

private struct LauncherLogDetail: View {
    let entry: LauncherLogEntry
    @State private var contentHeight: CGFloat = 1
    private var steps: [LauncherLogEntry.Step] { entry.steps.filter { $0.message != entry.detailMessage } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        heading
                        Spacer(minLength: 16)
                        actions.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        heading
                        actions.padding(.leading, 30)
                    }
                }
                if entry.status == .running {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.progress.stage)
                            Spacer()
                            if entry.progress.total > 0 {
                                Text(Messages.LauncherLog.transferProgress(Int64(entry.progress.completed), Int64(entry.progress.total)).localized).monospacedDigit()
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        if entry.progress.total > 0 { ProgressView(value: min(1, entry.progress.fraction)) }
                    }.padding(.leading, 30).frame(maxWidth: 960, alignment: .leading)
                }
                if let detail = entry.summary, detail != entry.title,
                   entry.status != .running || detail != entry.progress.stage {
                    Text(detail).font(.callout).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true).padding(.leading, 30)
                        .frame(maxWidth: 960, alignment: .leading)
                }
                if !steps.isEmpty {
                    Divider().padding(.leading, 30)
                    DisclosureGroup(Messages.SessionUI.technicalDetails.localized) {
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                        ForEach(steps.reversed()) { step in
                            GridRow(alignment: .firstTextBaseline) {
                                Text(step.date, format: .dateTime.hour().minute().second())
                                    .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
                                    .fixedSize()
                                Text(step.message.localized).font(.callout).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.padding(.top, 10).frame(maxWidth: 960, alignment: .leading)
                    }.font(.callout).padding(.leading, 30)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, 260))
        .background(.bar)
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            LauncherEntrySymbol(entry: entry).padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.title).font(.headline).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text(entry.statusTitle)
                        Text("·")
                        Text(entry.kind.title)
                        Text("·")
                        timestamp
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.statusTitle + " · " + entry.kind.title)
                        timestamp
                    }
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var timestamp: some View {
        Text(entry.updatedAt, format: .dateTime.year().month().day().hour().minute().second())
            .monospacedDigit().fixedSize()
    }

    private var actions: some View {
        HStack(spacing: 12) {
            LauncherEntryActions(entry: entry).labelStyle(.titleAndIcon)
        }.controlSize(.small).buttonStyle(.borderless)
    }
}
