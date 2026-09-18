import SwiftUI
import RuriCore
import RuriLocalization

enum YearActivityMode: String, CaseIterable, Identifiable {
    case day, week, cumulative
    var id: Self { self }
    var title: String {
        switch self {
        case .day: Messages.HomeActivity.day.localized
        case .week: Messages.HomeActivity.week.localized
        case .cumulative: Messages.HomeActivity.cumulative.localized
        }
    }
}

/// A stable calendar grid in all three modes. Weeks share one shade and one
/// hover target; cumulative credit never lights up days that haven't happened.
struct YearActivityGrid: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let activity: GameYearActivity
    let mode: YearActivityMode
    @State private var selection: Date?
    @State private var scrollTarget: Date?
    @FocusState private var focused: Bool

    private var maximum: Double {
        switch mode {
        case .day: activity.days.map(\.seconds).max() ?? 0
        case .week: activity.weeks.map(\.seconds).max() ?? 0
        case .cumulative: activity.seconds
        }
    }
    private var selectedDay: GameYearActivity.Day? { activity.days.first { $0.date == selection } }
    private var selectedWeek: GameYearActivity.Week? {
        guard let day = selectedDay else { return nil }
        return activity.weeks.first { $0.column == day.column }
    }

    var body: some View {
        ActivityChartLayout(columns: activity.weeks.count) {
            GeometryReader { viewport in
                ScrollViewReader { reader in
                    ScrollView(.horizontal, showsIndicators: true) {
                        grid(width: viewport.size.width)
                            .anchorPreference(key: ActivityGridBoundsKey.self, value: .bounds) { $0 }
                    }
                    .onChange(of: scrollTarget) { _, date in
                        if let date { reader.scrollTo(date, anchor: .center) }
                    }
                }
                .overlayPreferenceValue(ActivityGridBoundsKey.self) { anchor in
                    if let anchor, let day = selectedDay {
                        tooltip(day)
                            .frame(width: 208, height: 82)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.1), lineWidth: 0.75) }
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                            .position(tooltipPosition(day, grid: viewport[anchor], viewportWidth: viewport.size.width))
                            .transition(.identity)
                            // Position, background and text change in the same frame.
                            // Never interpolate the panel through intervening cells.
                            .transaction { transaction in
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
        }
        .focusable().focusEffectDisabled().focused($focused)
        .onMoveCommand { direction in move(direction) }
        .onExitCommand { selection = nil }
        .onChange(of: focused) { _, value in
            if !value { selection = nil }
        }
        .onChange(of: mode) { selection = nil }
        .onChange(of: activity.year) { selection = nil; scrollTarget = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Messages.HomeActivity.chartLabel.localized)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Messages.HomeActivity.keyboardHelp.localized)
        .accessibilityAdjustableAction { direction in
            if mode == .week { move(direction == .increment ? .right : .left) }
            else { move(direction == .increment ? .down : .up) }
        }
    }

    private func grid(width: CGFloat) -> some View {
        let layout = GridLayout(width: width, columns: activity.weeks.count)
        let maximum = maximum
        let selectedColumn = selectedDay?.column
        return ZStack(alignment: .topLeading) {
            monthLabels(layout)
            weekdayLabels(layout)
            ForEach(activity.weeks) { week in
                ForEach(week.days) { day in
                    let highlighted = !day.isFuture && (mode == .week ? selectedColumn == day.column : selection == day.date)
                    let value = mode == .week ? week.seconds : mode == .cumulative ? day.cumulativeSeconds : day.seconds
                    let future = day.isFuture
                    let level = value > 0 && maximum > 0 ? min(4, max(1, Int(ceil(value / maximum * 4)))) : 0
                    RoundedRectangle(cornerRadius: layout.side * 0.27, style: .continuous)
                        .fill(future ? Color.primary.opacity(0.025) : Self.color(level: level))
                        .overlay {
                            RoundedRectangle(cornerRadius: layout.side * 0.27, style: .continuous)
                                .strokeBorder(border(day: day, highlighted: highlighted), lineWidth: contrast == .increased ? 1 : highlighted ? 0.8 : 0.5)
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: highlighted)
                        }
                        .frame(width: layout.side, height: layout.side)
                        .id(day.date)
                        .position(layout.center(column: day.column, row: day.row))
                }
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                guard let position = layout.position(at: point),
                      let week = activity.weeks.first(where: { $0.column == position.column }) else {
                    if selection != nil { selection = nil }
                    return
                }
                let date: Date?
                if mode == .week {
                    date = week.isFuture ? nil : week.days.first(where: { !$0.isFuture })?.date
                } else {
                    date = week.days.first { $0.row == position.row && !$0.isFuture }?.date
                }
                if selection != date { selection = date }
            case .ended:
                if selection != nil { selection = nil }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: mode)
    }

    static func color(level: Int) -> Color {
        level == 0 ? .primary.opacity(0.045) : Theme.accent.opacity([0, 0.24, 0.44, 0.68, 0.94][min(4, max(0, level))])
    }

    private func border(day: GameYearActivity.Day, highlighted: Bool) -> Color {
        if highlighted { return .primary.opacity(contrast == .increased ? 0.65 : 0.28) }
        if Calendar.current.isDateInToday(day.date) { return Theme.accent.opacity(0.65) }
        return contrast == .increased ? .primary.opacity(0.35) : .clear
    }

    private func monthLabels(_ layout: GridLayout) -> some View {
        ForEach(activity.days.filter { Calendar.current.component(.day, from: $0.date) == 1 }) { day in
            Text(day.date.formatted(Date.FormatStyle(locale: LocalizationContext.current.formatLocale).month(.abbreviated)))
                .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .fixedSize()
                .offset(x: layout.center(column: day.column, row: 0).x - layout.side / 2, y: layout.top - 23)
        }
    }

    private func weekdayLabels(_ layout: GridLayout) -> some View {
        var calendar = Calendar.current
        calendar.locale = LocalizationContext.current.formatLocale
        return ForEach([1, 3, 5], id: \.self) { row in
            let index = (calendar.firstWeekday - 1 + row) % 7
            Text(calendar.veryShortWeekdaySymbols[index])
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary)
                .position(x: layout.weekdayX, y: layout.center(column: 0, row: row).y)
        }
    }

    private func tooltipPosition(_ day: GameYearActivity.Day, grid: CGRect, viewportWidth: CGFloat) -> CGPoint {
        let layout = GridLayout(width: grid.width, columns: activity.weeks.count)
        let row = mode == .week ? selectedWeek?.days.first?.row ?? day.row : day.row
        let center = layout.center(column: day.column, row: row)
        return CGPoint(x: min(viewportWidth - 108, max(108, grid.minX + center.x)), y: grid.minY + center.y - 56)
    }

    private func tooltip(_ day: GameYearActivity.Day) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(dateLabel(day)).font(.caption).monospacedDigit().foregroundStyle(.secondary)
            Text(LocalizedFormat.duration(value(day)))
                .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail(day)).font(.caption2).foregroundStyle(.secondary)
        }
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
        .contentTransition(.identity)
    }

    private func dateLabel(_ day: GameYearActivity.Day) -> String {
        let style = Date.FormatStyle(locale: LocalizationContext.current.formatLocale).month(.abbreviated).day()
        if mode == .week, let week = selectedWeek, let first = week.days.first, let last = week.days.last {
            return Messages.HistoryUI.timeRange(first.date.formatted(style), last.date.formatted(style)).localized
        }
        return day.date.formatted(style.weekday(.abbreviated))
    }

    private func value(_ day: GameYearActivity.Day) -> Double {
        switch mode {
        case .day: day.seconds
        case .week: selectedWeek?.seconds ?? 0
        case .cumulative: day.cumulativeSeconds
        }
    }

    private func detail(_ day: GameYearActivity.Day) -> String {
        switch mode {
        case .day: day.seconds > 0 ? Messages.HomeActivity.dayTime.localized : Messages.HistoryUI.noActivity.localized
        case .week: Messages.HomeActivity.activeDays(Int64(selectedWeek?.activeDays ?? 0)).localized
        case .cumulative: Messages.HomeActivity.dayContribution(LocalizedFormat.duration(day.seconds)).localized
        }
    }

    private var accessibilityValue: String {
        if let day = selectedDay { return dateLabel(day) + " · " + LocalizedFormat.duration(value(day)) + " · " + detail(day) }
        return mode.title + " · " + LocalizedFormat.duration(activity.seconds) + " · " + Messages.HomeActivity.activeDays(Int64(activity.activeDays)).localized
    }

    private func move(_ direction: MoveCommandDirection) {
        let candidates = activity.days.filter { !$0.isFuture }
        guard !candidates.isEmpty else { return }
        guard let index = candidates.firstIndex(where: { $0.date == selection }) else {
            selection = candidates.last?.date; scrollTarget = selection; return
        }
        let step: Int
        switch direction {
        case .left: step = -7
        case .right: step = 7
        case .up: step = mode == .week ? -7 : -1
        case .down: step = mode == .week ? 7 : 1
        @unknown default: return
        }
        selection = candidates[min(candidates.count - 1, max(0, index + step))].date
        scrollTarget = selection
    }
}

private struct ActivityGridBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// Give the chart its natural height at the proposed width, without a
/// measurement-state update or extra vertical space around smaller cells.
private struct ActivityChartLayout: Layout {
    let columns: Int

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 680
        return CGSize(width: width, height: GridLayout(width: width, columns: columns).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

private struct GridLayout {
    let columns: Int
    let width: CGFloat
    let height: CGFloat
    let side: CGFloat
    let pitch: CGFloat
    let top: CGFloat = 24
    let weekdayX: CGFloat = 9
    private let leading: CGFloat = 28

    init(width: CGFloat, columns: Int) {
        self.columns = columns
        self.width = max(680, width)
        let count = CGFloat(max(1, columns))
        // Fill the available width by scaling cells and their gaps together,
        // rather than capping cell size or stretching only the space between.
        let gapRatio: CGFloat = 0.27
        side = (self.width - leading) / (count * (1 + gapRatio) - gapRatio)
        pitch = side * (1 + gapRatio)
        height = top + 6 * pitch + side + 8
    }

    func center(column: Int, row: Int) -> CGPoint {
        CGPoint(x: leading + CGFloat(column) * pitch + side / 2, y: top + CGFloat(row) * pitch + side / 2)
    }

    func position(at point: CGPoint) -> (column: Int, row: Int)? {
        guard point.x >= leading, point.y >= top,
              point.x < leading + CGFloat(max(0, columns - 1)) * pitch + side,
              point.y < top + 6 * pitch + side else { return nil }
        let column = Int((point.x - leading) / pitch), row = Int((point.y - top) / pitch)
        guard column < columns, row < 7 else { return nil }
        return (column, row)
    }
}
