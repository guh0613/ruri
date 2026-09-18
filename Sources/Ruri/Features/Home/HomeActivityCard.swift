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
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 24) {
                                summary(loaded)
                                Spacer(minLength: 12)
                                controls(year: year, currentYear: currentYear)
                            }
                            VStack(alignment: .leading, spacing: 16) {
                                summary(loaded)
                                controls(year: year, currentYear: currentYear)
                            }
                        }
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

    private func summary(_ activity: GameYearActivity?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Messages.HomeActivity.totalTime.localized).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(activity.map { LocalizedFormat.duration($0.seconds) } ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                if let activity {
                    Text(Messages.HomeActivity.activeDays(Int64(activity.activeDays)).localized)
                        .font(.callout).foregroundStyle(.secondary).fixedSize()
                } else if error == nil {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func controls(year: Int, currentYear: Int) -> some View {
        HStack(spacing: 12) {
            Picker(Messages.HomeActivity.yearPicker.localized, selection: Binding(
                get: { year }, set: { selectedYear = $0 == currentYear ? nil : $0 }
            )) {
                ForEach(Array(stride(from: currentYear, through: min(year, activity?.firstRecordedYear ?? currentYear), by: -1)), id: \.self) { value in
                    Text(Messages.HomeActivity.year(String(value)).localized).tag(value)
                }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            Picker(Messages.HomeActivity.modePicker.localized, selection: $mode) {
                ForEach(YearActivityMode.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 178)
        }
        .fixedSize()
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
