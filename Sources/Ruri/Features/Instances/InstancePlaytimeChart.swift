import SwiftUI
import Charts
import RuriLocalization

struct InstancePlaytimeChart: View {
    struct Day: Identifiable {
        let date: Date
        let minutes: Double
        var id: Date { date }
        var durationLabel: String {
            Duration.seconds(minutes * 60).formatted(
                .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 3)
                    .locale(LocalizationContext.current.formatLocale)
            )
        }
    }

    let days: [Day]
    @State private var selectedDate: Date?
    private var selectedDay: Day? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value(Messages.AppLibraryView.date.localized, day.date, unit: .day),
                        y: .value(Messages.AppHomeView.playTime.localized, day.minutes))
                    .foregroundStyle(Theme.accent.gradient)
                    .cornerRadius(3)
                    .accessibilityLabel(LocalizedFormat.date(day.date, time: .omitted))
                    .accessibilityValue(day.durationLabel)
            }
            if let day = selectedDay {
                RuleMark(x: .value(Messages.AppLibraryView.date.localized, day.date, unit: .day))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .zIndex(-1)
                    .annotation(position: .top, spacing: 8,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedFormat.date(day.date, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(day.durationLabel).font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)) }
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        .fixedSize().allowsHitTesting(false).accessibilityHidden(true)
                    }
            }
        }
        // Swift Charts uses pointer hover for value selection on macOS.
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...max(60, days.map(\.minutes).max() ?? 0))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel { if let minutes = value.as(Double.self) { Text(LocalizedFormat.duration(minutes * 60)) } }
            }
        }
    }
}
