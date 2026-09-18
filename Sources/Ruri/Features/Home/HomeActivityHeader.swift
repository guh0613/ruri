import SwiftUI
import RuriCore
import RuriLocalization

struct HomeActivityHeader: View {
    let activity: GameYearActivity?
    let isLoading: Bool
    let year: Int
    let currentYear: Int
    let firstRecordedYear: Int?
    @Binding var selectedYear: Int?
    @Binding var mode: YearActivityMode

    private var valueFont: Font {
        .system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 28) {
                metrics.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 16)
                VStack(alignment: .trailing, spacing: 12) {
                    yearPicker
                    modePicker
                }
            }
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    metrics
                    VStack(alignment: .leading, spacing: 16) {
                        playTime
                        activeDays
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        yearPicker
                        Spacer(minLength: 12)
                        modePicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        yearPicker
                        modePicker
                    }
                }
            }
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 24) {
            playTime
            Rectangle().fill(.quaternary).frame(width: 1, height: 44)
                .padding(.top, 9)
                .accessibilityHidden(true)
            activeDays
        }
    }

    private var playTime: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Messages.HomeActivity.totalTime.localized, systemImage: "clock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let activity {
                    Text(duration(activity.seconds, units: [.hours, .minutes]))
                } else {
                    Text("—").font(valueFont)
                        .foregroundStyle(.secondary)
                }
                if isLoading { ProgressView().controlSize(.small) }
            }
            .frame(height: 36, alignment: .bottomLeading)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    private var activeDays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(Messages.HistoryUI.activeDays.localized, systemImage: "calendar")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Group {
                if let activity {
                    Text(duration(Double(activity.activeDays) * 86_400, units: [.days]))
                } else {
                    Text("—").font(valueFont)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 36, alignment: .bottomLeading)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
    }

    /// Keep localized units and ordering, with the same numeric and unit
    /// typography for both metrics.
    private func duration(_ seconds: Double, units: Set<Duration.UnitsFormatStyle.Unit>) -> AttributedString {
        var value = Duration.seconds(seconds).formatted(
            .units(allowed: units, width: .abbreviated, maximumUnitCount: 2)
                .locale(LocalizationContext.current.formatLocale).attributed
        )
        for run in value.runs {
            let isNumber = run.measurement == .value
            value[run.range].font = isNumber
                ? valueFont
                : .system(size: 16, weight: .medium)
            value[run.range].foregroundColor = isNumber ? .primary : .secondary
        }
        return value
    }

    private var yearPicker: some View {
        Picker(Messages.HomeActivity.yearPicker.localized, selection: Binding(
            get: { year }, set: { selectedYear = $0 == currentYear ? nil : $0 }
        )) {
            ForEach(Array(stride(from: currentYear, through: min(year, firstRecordedYear ?? currentYear), by: -1)), id: \.self) { value in
                Text(Messages.HomeActivity.year(String(value)).localized).tag(value)
            }
        }
        .labelsHidden().pickerStyle(.menu).fixedSize()
        .controlSize(.small)
    }

    private var modePicker: some View {
        Picker(Messages.HomeActivity.modePicker.localized, selection: $mode) {
            ForEach(YearActivityMode.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden().pickerStyle(.segmented).frame(width: 178, alignment: .trailing)
        .fixedSize()
    }
}
