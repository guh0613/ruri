import SwiftUI
import Charts
import RuriCore
import RuriLocalization

/// The activity column chart at the top of the history page. One column per day
/// or per month, always zero-filled, so a quiet week reads as a gap in the
/// rhythm rather than as missing data. The hovered column is reported to the
/// owner, which shows its value in the header instead of a floating callout
/// that the card would clip.
struct GameActivityChart: View {
    let buckets: [GameHistoryBucket]
    let daily: Bool
    @Binding var selection: Date?

    private var unit: Calendar.Component { daily ? .day : .month }
    private var peak: Double { buckets.map(\.seconds).max() ?? 0 }
    private var isEmpty: Bool { peak <= 0 }
    private var selected: GameHistoryBucket? { Self.bucket(for: selection, in: buckets, daily: daily) }

    var body: some View {
        Chart {
            ForEach(buckets) { bucket in
                BarMark(x: .value(Messages.SessionUI.date.localized, bucket.date, unit: unit),
                        y: .value(Messages.SessionUI.totalTime.localized, bucket.seconds))
                    .foregroundStyle(Theme.accent.gradient)
                    .opacity(selected == nil || selected?.date == bucket.date ? 1 : 0.35)
                    .cornerRadius(daily && buckets.count > 45 ? 1.5 : 4)
                    .accessibilityLabel(Self.label(bucket.date, daily: daily))
                    .accessibilityValue(LocalizedFormat.duration(bucket.seconds))
            }
            if let bucket = selected, bucket.seconds > 0 {
                RuleMark(x: .value(Messages.SessionUI.date.localized, bucket.date, unit: unit))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .zIndex(-1)
            }
        }
        // Swift Charts uses pointer hover for value selection on macOS.
        .chartXSelection(value: $selection)
        .chartYScale(domain: 0...max(1800, peak * 1.2))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(seconds <= 0 ? "" : LocalizedFormat.duration(seconds)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: daily ? (buckets.count > 14 ? 5 : 7) : 6)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(axisLabel(date)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartPlotStyle { $0.opacity(isEmpty ? 0.25 : 1) }
        .overlay {
            if isEmpty {
                Text(Messages.HistoryUI.noActivity.localized).font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(height: 190)
    }

    /// The column under a hover position, for the chart and its owner alike.
    static func bucket(for selection: Date?, in buckets: [GameHistoryBucket], daily: Bool) -> GameHistoryBucket? {
        guard let selection else { return nil }
        return buckets.first { Calendar.current.isDate($0.date, equalTo: selection, toGranularity: daily ? .day : .month) }
    }

    static func label(_ date: Date, daily: Bool) -> String {
        daily ? LocalizedFormat.date(date, time: .omitted)
              : date.formatted(Date.FormatStyle(locale: LocalizationContext.current.formatLocale).year().month(.wide))
    }
    private func axisLabel(_ date: Date) -> String {
        let locale = LocalizationContext.current.formatLocale
        return daily ? date.formatted(Date.FormatStyle(locale: locale).month(.abbreviated).day())
                     : date.formatted(Date.FormatStyle(locale: locale).month(.abbreviated))
    }
}
