import SwiftUI
import RuriCore
import RuriLocalization

/// Permanent play history, not a diagnostic file picker. Queries are paged and
/// run off the UI actor, including when an instance has since been deleted.
struct GameHistoryView: View {
    @Environment(AppModel.self) private var model
    private enum Period: String, CaseIterable {
        case all, week, month
        var title: String { switch self { case .all: Messages.SessionUI.allDates.localized; case .week: Messages.SessionUI.lastWeek.localized; case .month: Messages.SessionUI.lastMonth.localized } }
        var since: Date? {
            switch self { case .all: return nil; case .week, .month: return Calendar.current.date(byAdding: .day, value: self == .week ? -6 : -29, to: Calendar.current.startOfDay(for: Date())) }
        }
    }
    @State private var period = Period.all
    @State private var records: [GameSession] = []
    @State private var summary = GameHistorySummary()
    @State private var recentSeconds = 0.0
    @State private var search = ""
    @State private var problemsOnly = false
    @State private var selectedID: UUID?
    @State private var loading = false
    @State private var hasMore = false
    @State private var error: String?
    @State private var request = UUID()
    private var key: String { "\(model.historyInstanceID?.uuidString ?? "")|\(period.rawValue)|\(search)|\(problemsOnly)|\(model.historyRevision)|\(request)" }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text(Messages.SessionUI.historySubtitle.localized).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 24) {
                    SessionMetric(title: Messages.SessionUI.totalTime.localized, value: LocalizedFormat.duration(summary.seconds))
                    SessionMetric(title: Messages.SessionUI.playCount.localized, value: summary.playCount.formatted())
                    SessionMetric(title: Messages.SessionUI.recentTime.localized, value: LocalizedFormat.duration(recentSeconds))
                }
                HStack(spacing: 12) {
                    Picker(Messages.SessionUI.instance.localized, selection: $model.historyInstanceID) {
                        Text(Messages.SessionUI.allInstances.localized).tag(Optional<UUID>.none)
                        ForEach(model.state.instances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                    }.frame(maxWidth: 220)
                    Picker(Messages.SessionUI.date.localized, selection: $period) {
                        ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 125)
                    Toggle(Messages.SessionUI.problemsOnly.localized, isOn: $problemsOnly).toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                    TextField(Messages.SessionUI.search.localized, text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                }
            }.padding(24)
            Divider()
            Table(records, selection: $selectedID) {
                TableColumn(Messages.SessionUI.instance.localized) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.instanceName).fontWeight(.medium).lineLimit(1)
                        Text("Minecraft \(record.gameVersion) · \(record.loader)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 6)
                }.width(min: 160, ideal: 260)
                TableColumn(Messages.SessionUI.date.localized) { record in
                    Text(record.timing?.startedAt ?? record.exit?.startedAt ?? record.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .monospacedDigit().foregroundStyle(.secondary)
                }.width(min: 160, ideal: 190)
                TableColumn(Messages.SessionUI.duration.localized) { record in
                    Text(record.userDuration).monospacedDigit()
                }.width(min: 95, ideal: 130)
                TableColumn(Messages.SessionUI.result.localized) { record in
                    Label(record.userResult, systemImage: record.resultSymbol).foregroundStyle(record.resultColor).font(.callout)
                }.width(min: 100, ideal: 130)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let record = records.first(where: { ids.contains($0.id) }) {
                    Button(Messages.SessionUI.details.localized) { model.inspectSession(record) }
                }
            } primaryAction: { ids in
                if let record = records.first(where: { ids.contains($0.id) }) { model.inspectSession(record) }
            }
            .overlay {
                if records.isEmpty {
                    if loading { ProgressView() }
                    else {
                        ContentUnavailableView(search.isEmpty && !problemsOnly ? Messages.SessionUI.noHistory.localized : Messages.SessionUI.noMatches.localized,
                                               systemImage: "clock.arrow.circlepath", description: Text(Messages.SessionUI.noHistoryHelp.localized))
                    }
                }
            }
            Divider()
            HStack {
                if loading && !records.isEmpty { ProgressView().controlSize(.small) }
                if hasMore { Button(Messages.SessionUI.loadMore.localized) { Task { await loadMore() } }.disabled(loading) }
                Spacer()
                if let record = records.first(where: { $0.id == selectedID }) {
                    Button(Messages.SessionUI.details.localized) { model.inspectSession(record) }.buttonStyle(.borderedProminent)
                }
            }.padding(.horizontal, 24).padding(.vertical, 12)
            if let error = error ?? model.historyStorageError {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    Spacer()
                    Button(Messages.SessionUI.retry.localized) { request = UUID() }
                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
            Text(Messages.SessionRuntime.timingHelp.localized).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 16)
        }
        .background(.background)
        .task(id: key) {
            let generation = key
            loading = true; defer { if generation == key { loading = false } }
            let paths = model.paths, instanceID = model.historyInstanceID
            let query = GameHistoryQuery(instanceID: instanceID, since: period.since, search: search, problemsOnly: problemsOnly)
            do {
                try await Task.sleep(for: .milliseconds(180))
                let work = Task.detached(priority: .utility) {
                    let since = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: Date())) ?? Date()
                    return try (GameHistoryStore.list(paths: paths, query: query), GameHistoryStore.summary(paths: paths, instanceID: instanceID),
                                GameHistoryStore.days(paths: paths, instanceID: instanceID, since: since).reduce(0) { $0 + $1.seconds })
                }
                let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                records = value.0; summary = value.1; recentSeconds = value.2; hasMore = records.count == query.limit; error = nil
                model.historyStorageError = nil
                if !records.contains(where: { $0.id == selectedID }) { selectedID = nil }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func loadMore() async {
        guard !loading else { return }
        let generation = key, paths = model.paths
        loading = true; defer { if generation == key { loading = false } }
        let query = GameHistoryQuery(instanceID: model.historyInstanceID, since: period.since, search: search, problemsOnly: problemsOnly, offset: records.count)
        do {
            let value = try await Task.detached(priority: .utility) { try GameHistoryStore.list(paths: paths, query: query) }.value
            guard generation == key else { return }
            let known = Set(records.map(\.id))
            records += value.filter { !known.contains($0.id) }; hasMore = value.count == query.limit
        } catch { self.error = error.localizedDescription }
    }
}
