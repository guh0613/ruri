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
    @State private var loader = LoaderKind.vanilla
    @State private var loaderVersion = ""
    @State private var loaders: [String] = []
    @State private var search = ""
    @State private var snapshots = false
    @State private var loadingLoader = false
    @State private var loaderError: String?
    var versions: [VersionEntry] { (model.catalog?.versions ?? []).filter { (snapshots || $0.isRelease) && (search.isEmpty || $0.id.localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { SectionHeading(title: Messages.AppCreateInstanceView.createWorld.localized, subtitle: Messages.AppCreateInstanceView.createDescription.localized); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
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
            HStack {
                Picker(Messages.AppCreateInstanceView.loader.localized, selection: $loader) { ForEach(LoaderKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
            }
            if loader != .vanilla {
                if loader == .optifine { Text(Messages.AppCreateInstanceView.optifineSource.localized).font(.caption).foregroundStyle(.secondary) }
                if loadingLoader { ProgressView(Messages.AppCreateInstanceView.findCompatibleLoaders.localized).controlSize(.small) }
                else if let loaderError { Text(loaderError).font(.caption).foregroundStyle(.red) }
                else { Picker(Messages.AppCreateInstanceView.loaderVersion.localized, selection: $loaderVersion) { ForEach(loaders, id: \.self) { Text($0).tag($0) } } }
            }
            HStack {
                Text((model.state.settings.isolationPolicy ?? .always).directory(loader: loader).title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(Messages.AppCreateInstanceView.createAndInstall.localized) { model.install(name: name, version: selectedVersion, loader: loader, loaderVersion: loader == .vanilla ? nil : loaderVersion) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(selectedVersion.isEmpty || model.busy || (loader != .vanilla && (loaderVersion.isEmpty || loadingLoader)))
            }
        }.padding(28).frame(width: 570)
        .task { if model.catalog == nil { await model.refreshCatalog() }; if selectedVersion.isEmpty { selectedVersion = model.catalog?.latest.release ?? "" } }
        .task(id: selectedVersion + loader.rawValue) {
            loaders = []; loaderVersion = ""; loaderError = nil
            guard loader != .vanilla, !selectedVersion.isEmpty else { return }
            loadingLoader = true
            do {
                let result = try await model.installer.loaderVersions(loader, game: selectedVersion)
                try Task.checkCancellation(); loaders = result; loaderVersion = result.first ?? ""
                if result.isEmpty { loaderError = Messages.AppCreateInstanceView.noCompatibleLoader.localized }
            } catch { if !Task.isCancelled { loaderError = error.localizedDescription } }
            loadingLoader = false
        }
    }
}
