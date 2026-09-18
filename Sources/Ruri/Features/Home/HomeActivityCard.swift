import SwiftUI
import RuriCore
import RuriLocalization

struct HomeActivityCard: View {
    @Environment(AppModel.self) private var model
    @State private var selectedYear: Int?
    @State private var mode = YearActivityMode.day
    @State private var activity: GameYearActivity?
    @State private var error: String?
    @State private var request = UUID()

    var body: some View {
        // Also refresh the calendar boundary when the home page stays open overnight.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let currentYear = Calendar.current.component(.year, from: context.date)
            let year = selectedYear ?? currentYear
            let loaded = activity?.year == year ? activity : nil
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(Messages.HomeActivity.title.localized) {
                    Button { model.showHistory() } label: {
                        HStack(spacing: 4) {
                            Text(Messages.HomeActivity.openHistory.localized)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                }
                Surface(padding: 24) {
                    VStack(alignment: .leading, spacing: 18) {
                        HomeActivityHeader(activity: loaded, isLoading: loaded == nil && error == nil,
                                           year: year, currentYear: currentYear,
                                           firstRecordedYear: activity?.firstRecordedYear,
                                           selectedYear: $selectedYear, mode: $mode)
                        Divider()
                        YearActivityGrid(activity: loaded ?? GameYearActivity(year: year, now: context.date), mode: mode)
                            .opacity(loaded == nil ? 0.45 : 1)
                            .allowsHitTesting(loaded != nil)
                            .accessibilityHidden(loaded == nil)
                        footer
                    }
                }
            }
            .task(id: loadKey(year: year, date: context.date)) { await load(year: year, now: context.date) }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            legend.frame(maxWidth: .infinity, alignment: .trailing)
            if let error {
                HStack(spacing: 8) {
                    Label(Messages.HomeActivity.loadFailed.localized, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary).help(error)
                    Button(Messages.SessionUI.retry.localized) { request = UUID() }.buttonStyle(.link)
                }.font(.caption)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 5) {
            Text(Messages.HomeActivity.less.localized).padding(.trailing, 2)
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(YearActivityGrid.color(level: level)).frame(width: 10, height: 10)
            }
            Text(Messages.HomeActivity.more.localized).padding(.leading, 2)
        }
        .font(.caption2).foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Messages.HomeActivity.legendHelp.localized)
    }

    private func loadKey(year: Int, date: Date) -> String {
        "\(year)|\(model.historyRevision)|\(request)|\(Calendar.current.startOfDay(for: date))|\(TimeZone.current.identifier)|\(Calendar.current.firstWeekday)"
    }

    private func load(year: Int, now: Date) async {
        let paths = model.paths, calendar = Calendar.current
        error = nil
        let work = Task.detached(priority: .utility) {
            try GameHistoryStore.yearActivity(paths: paths, year: year, calendar: calendar, now: now)
        }
        do {
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            activity = result
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
