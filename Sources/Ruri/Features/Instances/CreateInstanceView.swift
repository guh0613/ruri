import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct CreateInstanceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedVersion = ""
    @State private var selections: [LoaderSelection] = []
    @State private var loadersValid = true
    @State private var search = ""
    @State private var snapshots = false
    var versions: [VersionEntry] { (model.catalog?.versions ?? []).filter { (snapshots || $0.isRelease) && (search.isEmpty || $0.id.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { SectionHeading(title: Messages.AppCreateInstanceView.createInstance.localized); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            TextField(Messages.AppCreateInstanceView.instanceNameOptional.localized, text: $name).textFieldStyle(.roundedBorder)
            Label(Messages.AppCreateInstanceView.saveLocation(String(describing: model.selectedDirectoryName)).localized, systemImage: "folder").font(.callout).foregroundStyle(.secondary)
            HStack { TextField(Messages.AppCreateInstanceView.searchVersions.localized, text: $search).textFieldStyle(.roundedBorder); Toggle(Messages.AppCreateInstanceView.snapshotsAndOldVersions.localized, isOn: $snapshots).toggleStyle(.checkbox) }
            if model.catalogLoading && model.catalog == nil { ProgressView(Messages.AppCreateInstanceView.fetchingVersions.localized).frame(maxWidth: .infinity, minHeight: 220) }
            else if let error = model.catalogError, model.catalog == nil {
                VStack { Text(error).foregroundStyle(.secondary); Button(Messages.AppCreateInstanceView.retry.localized) { Task { await model.refreshCatalog() } } }.frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List(versions, selection: $selectedVersion) { version in
                    HStack {
                        Text(version.id).font(.system(.body, design: .monospaced).weight(.medium))
                        if version.id == model.catalog?.latest.release { TagPill(text: Messages.AppCreateInstanceView.latestRelease.localized) }
                        Spacer()
                        Text(LocalizedFormat.publishedDate(version.releaseTime)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(version.id)
                }.listStyle(.bordered).frame(height: 230)
            }
            LoaderSelectionView(game: selectedVersion, selections: $selections, isValid: $loadersValid)
            HStack {
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppCreateInstanceView.createAndInstall.localized) { model.install(name: name, version: selectedVersion, selections: selections) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selectedVersion.isEmpty || model.busy || !loadersValid)
            }
        }.padding(28).frame(width: 570)
        .task { if model.catalog == nil { await model.refreshCatalog() }; if selectedVersion.isEmpty { selectedVersion = model.catalog?.latest.release ?? "" } }
    }
}
