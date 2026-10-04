import SwiftUI
import RuriCore
import RuriLocalization

/// Time spent on one server: the last 30 days as a chart, the total for the
/// chosen instance, and each visit, which opens the run it belongs to.
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
    @State private var loaded = false
    @State private var error: String?
    private var current: ServerPlaySummary? { instanceID == nil ? summary : filteredSummary }
    private var key: String { address.key + (instanceID?.uuidString ?? "") + model.historyRevision.uuidString }
    private var playedInstances: [GameInstance] { model.state.instances.filter { summary?.instanceIDs.contains($0.id) == true } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(Messages.Servers.history.localized) {
                if playedInstances.count > 1 {
                    Picker(Messages.Servers.instanceName.localized, selection: $instanceID) {
                        Text(Messages.Servers.allInstances.localized).tag(nil as UUID?)
                        ForEach(playedInstances) { instance in Text(instance.name).tag(Optional(instance.id)) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .lineLimit(1).truncationMode(.middle)
                    .frame(minWidth: 0, idealWidth: 200, maxWidth: 240)
                    .help(playedInstances.first { $0.id == instanceID }?.name ?? Messages.Servers.allInstances.localized)
                }
            }
            Surface(padding: 0) {
                if loaded {
                    VStack(alignment: .leading, spacing: 0) {
                        overview.padding(20)
                        Divider()
                        visitList
                    }
                } else {
                    DelayedProgressView().frame(maxWidth: .infinity, minHeight: 254)
                }
            }
            if let error = error ?? historyError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
        }
        .task(id: key) { await load(more: false) }
    }

    private var overview: some View {
        let recent = days.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Messages.Servers.last30Days.localized).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if recent > 0 {
                        Text(LocalizedFormat.duration(recent * 60)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    } else {
                        Text(Messages.Servers.noRecentPlay.localized).font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 16)
                if let current {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Messages.Servers.playtime.localized).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Text(LocalizedFormat.duration(current.seconds)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                        if current.estimatedSeconds > 0 {
                            HStack(spacing: 4) {
                                Text(Messages.Servers.estimatedPortion(LocalizedFormat.duration(current.estimatedSeconds)).localized)
                                Image(systemName: "info.circle")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            .help(Messages.Servers.estimateHint.localized)
                        }
                    }
                }
            }
            InstancePlaytimeChart(days: days).frame(height: 130)
        }
    }

    @ViewBuilder private var visitList: some View {
        if visits.isEmpty {
            Text(Messages.Servers.noHistory.localized).font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
        } else {
            ForEach(visits) { visit in
                ServerVisitRow(visit: visit, instance: model.state.instances.first { $0.id == visit.instanceID })
                if visit.id != visits.last?.id { Divider().padding(.leading, 54) }
            }
            if hasMore {
                Divider()
                Button { Task { await load(more: true) } } label: {
                    Group {
                        if loading { ProgressView().controlSize(.small) } else { Text(Messages.SessionUI.loadMore.localized) }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(loading)
            }
        }
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
        if generation == key { loaded = true }
    }
}

private struct ServerVisitRow: View {
    @Environment(AppModel.self) private var model
    let visit: GameActivityVisit
    let instance: GameInstance?
    @State private var hovering = false
    var body: some View {
        Button {
            do { if let record = try GameHistoryStore.load(paths: model.paths, sessionID: visit.sessionID) { model.inspectSession(record) } }
            catch { model.error = error.localizedDescription }
        } label: {
            HStack(spacing: 12) {
                InstanceIcon(instance, size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(instance?.name ?? visit.instanceName).font(.callout.weight(.medium)).lineLimit(1)
                    Text(LocalizedFormat.date(visit.segment.startedAt)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if visit.segment.quality != .observed {
                    TagPill(text: Messages.Servers.estimated.localized, color: .secondary).help(Messages.Servers.estimateHint.localized)
                }
                Text(LocalizedFormat.duration(visit.segment.seconds)).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.primary.opacity(hovering ? 0.045 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
