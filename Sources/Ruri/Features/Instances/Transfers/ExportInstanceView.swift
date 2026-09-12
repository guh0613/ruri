import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ExportInstanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var format = InstanceExportFormat.ruri
    @State private var includeWorlds = true
    @State private var details = ModpackExportDetails()
    private var localInstallation: Bool { instance.repositoryVersionID != nil || instance.importedInstallation != nil }
    private var complete: Bool { format == .complete || (format == .ruri && localInstallation) }
    private var containsCommands: Bool { !instance.resolvedLaunchSettings(defaults: model.state.settings).commands.isEmpty }
    private var formats: [InstanceExportFormat] { localInstallation ? [.complete] : containsCommands ? [.ruri, .complete] : InstanceExportFormat.allCases }
    init(instance: GameInstance) {
        self.instance = instance
        _format = State(initialValue: instance.repositoryVersionID != nil || instance.importedInstallation != nil ? .complete : .ruri)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(Messages.AppExportInstanceView.bodyText1(String(describing: instance.name)).localized, systemImage: "square.and.arrow.up").font(.title2.bold())
            Text(complete ? Messages.AppExportInstanceView.bodyText2.localized : Messages.AppExportInstanceView.bodyText3.localized).foregroundStyle(.secondary)
            Picker(Messages.AppExportInstanceView.bodyText4.localized, selection: $format) { ForEach(formats) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            if format == .mcbbs || format == .mrpack {
                LabeledContent(Messages.AppExportInstanceView.bodyText5.localized) { TextField(Messages.AppExportInstanceView.bodyText6.localized, text: $details.version).textFieldStyle(.roundedBorder) }
                if format == .mcbbs { LabeledContent(Messages.AppExportInstanceView.bodyText7.localized) { TextField(Messages.AppExportInstanceView.bodyText7.localized, text: $details.author).textFieldStyle(.roundedBorder) } }
                TextField(Messages.AppExportInstanceView.bodyText8.localized, text: $details.description, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
            }
            if format == .mrpack { Toggle(Messages.AppExportInstanceView.bodyText9.localized, isOn: $details.referenceDownloads) }
            Toggle(Messages.AppExportInstanceView.bodyText10.localized, isOn: $includeWorlds)
            if containsCommands { Text(Messages.AppExportInstanceView.bodyText11.localized).font(.caption).foregroundStyle(.secondary) }
            if !instance.resolvedLaunchSettings(defaults: model.state.settings).environment.isEmpty {
                Text(Messages.AppExportInstanceView.bodyText12.localized).font(.caption).foregroundStyle(.secondary)
            }
            if instance.resolvedLaunchSettings(defaults: model.state.settings).java.major != nil, format != .ruri && format != .complete {
                Text(Messages.AppExportInstanceView.bodyText13.localized).font(.caption).foregroundStyle(.secondary)
            }
            Text(complete ? Messages.AppExportInstanceView.bodyText14.localized : format == .ruri ? Messages.AppExportInstanceView.bodyText15.localized : format == .mcbbs ? Messages.AppExportInstanceView.bodyText16.localized : format == .mrpack ? Messages.AppExportInstanceView.bodyText17.localized : Messages.AppExportInstanceView.bodyText18.localized).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(Messages.AppExportInstanceView.bodyText19.localized) { chooseDestination() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(model.busy || model.isInstanceInUse(instance.id))
            }
        }.padding(26).frame(width: 510)
    }
    private func chooseDestination() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [format == .mrpack ? (UTType(filenameExtension: "mrpack") ?? .zip) : .zip]
        panel.nameFieldStringValue = instance.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + (format == .mrpack ? ".mrpack" : ".zip")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.export(instance, to: url, format: format, includeWorlds: includeWorlds, details: details); dismiss()
    }
}
