import RuriLocalization
import SwiftUI
import RuriCore

struct InstanceComponentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var selections: [LoaderSelection]
    @State private var loadersValid = false
    @State private var backup: ComponentBackup?
    private var reason: String? { InstanceComponents.unavailableReason(instance) }
    private var changed: Bool { LoaderSelection.ordered(selections) != instance.loaderSelections }

    init(instance: GameInstance) {
        self.instance = instance; _selections = State(initialValue: instance.loaderSelections)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: Messages.AppInstanceComponentsView.manageLoader.localized,
                           subtitle: instance.name + " · " + Messages.Discovery.minecraftVersion(instance.gameVersion).localized)
            LabeledContent(Messages.AppInstanceComponentsView.current.localized, value: instance.loaderSummary)
            if let reason { Label(reason, systemImage: "info.circle").foregroundStyle(.secondary) }
            else {
                LoaderSelectionView(game: instance.gameVersion, selections: $selections, isValid: $loadersValid)
                Text(Messages.AppInstanceComponentsView.applyLoaderDetails.localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let backup {
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        Text(Messages.AppInstanceComponentsView.previousComponents(backup.title).localized).font(.callout)
                        Text(LocalizedFormat.date(backup.createdAt, date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(Messages.AppInstanceComponentsView.restorePreviousConfiguration.localized) { model.restoreComponents(instance); dismiss() }
                        .disabled(model.busy || model.isInstanceInUse(instance.id))
                }
            }
            HStack {
                Spacer()
                Button(Messages.AppInstanceComponentsView.close.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                if reason == nil {
                    Button(selections.isEmpty ? Messages.AppInstanceComponentsView.removeLoader.localized : Messages.AppInstanceComponentsView.applyLoader.localized) {
                        model.changeComponents(instance, selections: selections); dismiss()
                    }.buttonStyle(.borderedProminent)
                        .disabled(!changed || model.busy || model.isInstanceInUse(instance.id) || !loadersValid)
                }
            }
        }.padding(24).frame(width: 560)
        .task {
            do { backup = try await InstanceComponents(paths: model.paths).backup(for: instance.id) }
            catch { model.report(error.localizedDescription, level: .error) }
        }
    }
}
