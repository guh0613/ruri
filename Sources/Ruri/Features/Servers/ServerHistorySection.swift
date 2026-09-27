import SwiftUI
import RuriCore
import RuriLocalization

struct ServerHistorySection: View {
    @Environment(AppModel.self) private var model
    let address: ServerAddress
    let summary: ServerPlaySummary?
    let historyError: String?
    @State private var instanceID: UUID?
    @State private var filteredSummary: ServerPlaySummary?
    @State private var visits: [GameActivityVisit] = []
    @State private var days: [InstancePlaytimeChart.Day] = []
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    private var current: ServerPlaySummary? { instanceID == nil ? summary : filteredSummary }
    private var key: String { address.key + (instanceID?.uuidString ?? "") + model.historyRevision.uuidString }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Messages.Servers.history.localized).font(.title3.weight(.semibold))
                Spacer()
                Picker(Messages.Servers.instanceName.localized, selection: $instanceID) {
                    Text(Messages.Servers.all.localized).tag(nil as UUID?)
                    ForEach(model.state.instances.filter { summary?.instanceIDs.contains($0.id) == true }) { instance in Text(instance.name).tag(Optional(instance.id)) }
                }.frame(maxWidth: 220)
            }
            if let current {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    VStack(alignment: .leading) {
                        Text(Messages.Servers.playtime.localized).font(.caption).foregroundStyle(.secondary)
                        Text(LocalizedFormat.duration(current.seconds)).font(.title2.weight(.semibold)).monospacedDigit()
                    }
                    if current.estimatedSeconds > 0 {
                        VStack(alignment: .leading) {
                            Text(Messages.Servers.estimated.localized).font(.caption).foregroundStyle(.secondary)
                            Text(LocalizedFormat.duration(current.estimatedSeconds)).monospacedDigit()
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(Messages.Servers.lastPlayed.localized).font(.caption).foregroundStyle(.secondary)
                        Text(current.lastPlayed, style: .relative)
                    }
                }
                if !days.isEmpty { InstancePlaytimeChart(days: days).frame(height: 140) }
            } else { Text(Messages.Servers.unavailableTime.localized).foregroundStyle(.secondary) }
            Text(Messages.Servers.estimateHint.localized).font(.caption).foregroundStyle(.secondary)
            if let error = error ?? historyError { Text(error).font(.callout).foregroundStyle(.orange) }
            if visits.isEmpty && !loading { Text(Messages.Servers.noHistory.localized).font(.callout).foregroundStyle(.secondary) }
            ForEach(visits) { visit in
                Button {
                    do { if let record = try GameHistoryStore.load(paths: model.paths, sessionID: visit.sessionID) { model.inspectSession(record) } }
                    catch { model.error = error.localizedDescription }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(visit.instanceName).fontWeight(.medium)
                            Text(visit.segment.startedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if visit.segment.quality != .observed { Text(Messages.Servers.estimated.localized).font(.caption).foregroundStyle(.secondary) }
                        Text(LocalizedFormat.duration(visit.segment.seconds)).monospacedDigit()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if hasMore { Button(Messages.SessionUI.loadMore.localized) { Task { await load(more: true) } }.disabled(loading) }
        }
        .task(id: key) { await load(more: false) }
    }
    private func load(more: Bool) async {
        let generation = key, paths = model.paths, address = address, instanceID = instanceID, offset = more ? visits.count : 0
        loading = true; defer { if key == generation { loading = false } }
        do {
            let result = try await Task.detached(priority: .utility) {
                let records = try GameActivityStore.visits(paths: paths, server: address, instanceID: instanceID, limit: 50, offset: offset)
                let stats = try GameActivityStore.servers(paths: paths, instanceID: instanceID).first { $0.id == address.key }
                let start = Calendar.current.date(byAdding: .day, value: -29, to: Calendar.current.startOfDay(for: .now))!
                let measured = try GameActivityStore.days(paths: paths, server: address, instanceID: instanceID, since: start)
                return (records, stats, measured, start)
            }.value
            guard !Task.isCancelled, generation == key else { return }
            if more { let ids = Set(visits.map(\.id)); visits += result.0.filter { !ids.contains($0.id) } } else { visits = result.0 }
            filteredSummary = result.1; hasMore = result.0.count == 50; error = nil
            let measured = Dictionary(result.2.map { (Calendar.current.startOfDay(for: $0.date), $0.seconds) }, uniquingKeysWith: +)
            days = (0..<30).compactMap { index in
                Calendar.current.date(byAdding: .day, value: index, to: result.3).map { .init(date: $0, minutes: (measured[$0] ?? 0) / 60) }
            }
        } catch { if !Task.isCancelled, generation == key { self.error = error.localizedDescription } }
    }
}
