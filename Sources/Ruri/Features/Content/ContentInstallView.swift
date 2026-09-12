import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ContentInstallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: ModrinthProject
    @State private var versions: [ModrinthVersion] = []
    @State private var selectedVersion = ""
    @State private var instanceID: UUID?
    @State private var loading = false
    @State private var error: String?
    private let service = ModrinthService()
    var instance: GameInstance? { model.state.instances.first { $0.id == instanceID } }
    var isPack: Bool { project.project_type == "modpack" }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: project.title, subtitle: "by \(project.author)")
            Text(project.description).font(.callout).foregroundStyle(.secondary).lineLimit(5)
            if !isPack {
                Picker(Messages.AppContentInstallView.installToInstance.localized, selection: $instanceID) {
                    Text(Messages.AppContentInstallView.chooseInstance.localized).tag(nil as UUID?)
                    ForEach(model.state.instances.filter(\.installed)) { Text($0.name + " · " + $0.subtitle).tag(Optional($0.id)) }
                }
            }
            if loading { ProgressView(Messages.AppContentInstallView.findCompatibleVersions.localized) }
            else if !versions.isEmpty {
                Picker(Messages.AppContentInstallView.contentVersion.localized, selection: $selectedVersion) { ForEach(versions) { Text($0.name).tag($0.id) } }
            } else { Text(isPack || instance != nil ? Messages.AppContentInstallView.noCompatibleVersions.localized : Messages.AppContentInstallView.chooseInstalledInstance.localized).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            if project.project_type == "shader" { Text(Messages.AppContentInstallView.shaderHelp.localized).font(.caption).foregroundStyle(.secondary) }
            if project.project_type == "mod" { Text(Messages.AppContentInstallView.dependencyHelp.localized).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if let page = project.pageURL { Link(Messages.AppContentInstallView.viewOnModrinth.localized, destination: page) }
                Spacer(); Button(Messages.Common.cancel.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isPack ? Messages.AppContentInstallView.viewModpack.localized : Messages.AppContentInstallView.installContent.localized) {
                    guard let version = versions.first(where: { $0.id == selectedVersion }) else { return }
                    model.installContent(project: project, version: version, instance: instance); dismiss()
                }.buttonStyle(.borderedProminent).disabled(loading || selectedVersion.isEmpty || model.busy || (!isPack && (instance == nil || model.isInstanceInUse(instanceID))))
            }
        }.padding(30).frame(width: 570)
        .onAppear { instanceID = model.selected?.id }
        .task(id: instanceID) {
            versions = []; selectedVersion = ""; error = nil
            guard isPack || instance != nil else { return }
            loading = true
            do {
                let result = try await service.versions(project: project.id, game: isPack ? nil : instance?.gameVersion, loader: project.project_type == "mod" ? instance?.loader.modrinthLoader : nil)
                try Task.checkCancellation(); versions = result; selectedVersion = result.first?.id ?? ""
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            loading = false
        }
    }
}
