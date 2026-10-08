import RuriLocalization
import SwiftUI
import RuriCore

struct DownloadCacheRow: View {
    @Environment(AppModel.self) private var model
    @State private var summary: CacheMaintenance.Summary?
    @State private var cleaning = false
    /// The last cleanup's result stays until there is something to free again.
    @State private var freed: Int64?
    private var title: String { Messages.AppPreferencesView.downloadCache.localized }
    private var button: String { Messages.AppPreferencesView.cleanCache.localized }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                detail.font(.caption).foregroundStyle(.secondary).contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            if cleaning { ProgressView().controlSize(.small) }
            else if freed == nil {
                Button(button) { clean() }
                    .disabled(model.busy || model.isPresentingSheet || model.readOnly || (summary?.bytes ?? 0) == 0)
                    .accessibilityLabel(Messages.AppSettingsLayout.actionLabel(title, button).localized)
            }
        }
        .padding(.vertical, 3)
        .animation(.default, value: cleaning)
        .animation(.default, value: freed)
        // Measure again whenever an operation finishes, including the cleanup itself.
        .task(id: model.busy) {
            guard !model.busy else { return }
            let value = await model.cacheSummary()
            summary = value
            if value.bytes > 0, !cleaning { freed = nil }
        }
    }
    @ViewBuilder private var detail: some View {
        if cleaning { Text(Messages.AppPreferencesView.cleaningInProgress.localized) }
        else if let freed, freed > 0 {
            Label { Text(Messages.AppPreferencesView.cacheCleaned(LocalizedFormat.bytes(freed)).localized) } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            }
        } else if let summary {
            Text(summary.bytes > 0 ? Messages.AppPreferencesView.reclaimableSpace(LocalizedFormat.bytes(summary.bytes)).localized
                 : Messages.AppPreferencesView.nothingToReclaim.localized)
        } else { Text(Messages.AppPreferencesView.measuringCache.localized) }
    }
    private func clean() {
        cleaning = true
        let started = model.cleanCache { result in
            freed = result.bytes; cleaning = false
        }
        if !started { cleaning = false }
    }
}
