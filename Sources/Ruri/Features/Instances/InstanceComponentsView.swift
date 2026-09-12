import RuriLocalization
import SwiftUI
import RuriCore

struct InstanceComponentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var loader: LoaderKind
    @State private var version: String
    @State private var versions: [String] = []
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0
    @State private var backup: ComponentBackup?
    private var reason: String? { InstanceComponents.unavailableReason(instance) }
    private var changed: Bool { loader != instance.loader || (loader != .vanilla && version != instance.loaderVersion) }

    init(instance: GameInstance) {
        self.instance = instance; _loader = State(initialValue: instance.loader)
        _version = State(initialValue: instance.loaderVersion ?? "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: Messages.AppInstanceComponentsView.bodyText1.localized, subtitle: instance.name + " · Minecraft " + instance.gameVersion)
            LabeledContent(Messages.AppInstanceComponentsView.bodyText2.localized, value: instance.loader.title + (instance.loaderVersion.map { " " + $0 } ?? ""))
            if let reason { Label(reason, systemImage: "info.circle").foregroundStyle(.secondary) }
            else {
                Picker(Messages.AppInstanceComponentsView.reasonText1.localized, selection: $loader) {
                    ForEach(LoaderKind.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                if loader != .vanilla {
                    if loader == .optifine { Text(Messages.AppInstanceComponentsView.reasonText2.localized).font(.caption).foregroundStyle(.secondary) }
                    if loading { ProgressView(Messages.AppInstanceComponentsView.reasonText3.localized).controlSize(.small) }
                    else if let error {
                        Text(error).font(.callout).foregroundStyle(.orange)
                        Button(Messages.AppInstanceComponentsView.errorText1.localized) { retry += 1 }
                    } else {
                        Picker(Messages.AppInstanceComponentsView.errorText2.localized, selection: $version) {
                            ForEach(versions, id: \.self) { value in
                                Text(value + (loader == instance.loader && value == instance.loaderVersion ? Messages.AppInstanceComponentsView.errorText3.localized : "")).tag(value)
                            }
                        }
                    }
                }
                Text(loader == .vanilla ? Messages.AppInstanceComponentsView.errorText4.localized : Messages.AppInstanceComponentsView.errorText5.localized)
                    .font(.callout).foregroundStyle(.secondary)
                Text(Messages.AppInstanceComponentsView.errorText6.localized)
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
                    Button(Messages.AppInstanceComponentsView.backupText2.localized) { model.restoreComponents(instance); dismiss() }
                        .disabled(model.busy || model.isInstanceInUse(instance.id))
                }
            }
            HStack {
                Spacer()
                Button(Messages.AppInstanceComponentsView.backupText3.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                if reason == nil {
                    Button(loader == .vanilla ? Messages.AppInstanceComponentsView.backupText4.localized : Messages.AppInstanceComponentsView.backupText5.localized) {
                        model.changeComponents(instance, loader: loader, version: loader == .vanilla ? nil : version); dismiss()
                    }.buttonStyle(.borderedProminent)
                        .disabled(!changed || model.busy || model.isInstanceInUse(instance.id) || (loader != .vanilla && (loading || error != nil || version.isEmpty)))
                }
            }
        }.padding(24).frame(width: 560)
        .task {
            do { backup = try await InstanceComponents(paths: model.paths).backup(for: instance.id) }
            catch { model.notice = error.localizedDescription }
        }
        .task(id: loader.rawValue + String(retry)) {
            guard reason == nil else { return }
            versions = []; version = ""; error = nil; loading = loader != .vanilla
            guard loader != .vanilla else { return }
            do {
                var result = try await model.installer.loaderVersions(loader, game: instance.gameVersion)
                try Task.checkCancellation()
                if loader == instance.loader, let current = instance.loaderVersion {
                    if !result.contains(current) { result.insert(current, at: 0) }
                    version = current
                } else { version = result.first ?? "" }
                versions = result
                if result.isEmpty { error = Messages.AppInstanceComponentsView.currentText1.localized }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
    }
}
