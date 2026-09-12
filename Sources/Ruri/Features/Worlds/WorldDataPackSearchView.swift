import RuriLocalization
import SwiftUI
import RuriCore

struct WorldDataPackSearchView: View {
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    let world: WorldSnapshot
    @State private var query = ""
    @State private var offset = 0
    @State private var projects: [ModrinthProject] = []
    @State private var total = 0
    @State private var loading = false
    @State private var error: String?
    @State private var selected: ModrinthProject?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionHeading(title: Messages.AppWorldDataPackSearchView.bodyText1.localized, subtitle: world.name + " · Minecraft " + instance.gameVersion + " · Modrinth")
                Spacer(); Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField(Messages.AppWorldDataPackSearchView.bodyText2.localized, text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { offset = 0 }
            if let error { Text(error).foregroundStyle(.orange) }
            if loading { ProgressView(Messages.AppWorldDataPackSearchView.errorText1.localized).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if projects.isEmpty { EmptyPanel(symbol: "magnifyingglass", title: Messages.AppWorldDataPackSearchView.errorText2.localized, detail: Messages.AppWorldDataPackSearchView.errorText3.localized) }
            else {
                List(projects) { project in
                    Button { selected = project } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: project.icon_url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "shippingbox") }.frame(width: 38, height: 38)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(project.title).font(.headline)
                                Text(project.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(project.author).font(.caption).foregroundStyle(.tertiary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.listStyle(.bordered)
            }
            HStack {
                Text(Messages.AppWorldDataPackSearchView.errorText4(Int64(total)).localized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Messages.AppWorldDataPackSearchView.errorText5.localized) { offset = max(0, offset - 20) }.disabled(loading || offset == 0)
                Button(Messages.AppWorldDataPackSearchView.errorText6.localized) { offset += 20 }.disabled(loading || offset + 20 >= total)
            }
        }.padding(24).frame(width: 730, height: 600)
        .sheet(item: $selected) { project in WorldDataPackInstallView(instance: instance, world: world, project: project) }
        .task(id: "\(query):\(offset)") {
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(250))
                let result = try await WorldDataPackDownloads().search(query, game: instance.gameVersion, offset: offset)
                try Task.checkCancellation(); projects = result.hits; total = result.total_hits; loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
}

private struct WorldDataPackInstallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    let world: WorldSnapshot
    let project: ModrinthProject
    @State private var versions: [ModrinthVersion] = []
    @State private var selectedID: String?
    @State private var includePreviews = false
    @State private var loading = true
    @State private var error: String?
    @State private var plan: WorldDataPackDownloadPlan?
    @State private var resolution: Task<Void, Never>?
    private var filtered: [ModrinthVersion] { versions.filter { includePreviews || $0.version_type == nil || $0.version_type == "release" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: project.title, subtitle: Messages.AppWorldDataPackSearchView.bodyText3(String(describing: world.name), String(describing: instance.gameVersion)).localized)
            if loading || resolution != nil { ProgressView(loading ? Messages.AppWorldDataPackSearchView.bodyText4.localized : Messages.AppWorldDataPackSearchView.bodyText5.localized) }
            if let plan {
                Text(Messages.AppWorldDataPackSearchView.planText1(Int64(plan.files.count), String(describing: LocalizedFormat.bytes(plan.downloadSize))).localized).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(plan.versions) { version in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.name).font(.headline)
                                Text(version.version_number + (version.project_id == project.id ? "" : Messages.AppWorldDataPackSearchView.planText2.localized)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 240)
                Text(Messages.AppWorldDataPackSearchView.planText3.localized).font(.caption).foregroundStyle(.secondary)
            } else if !loading {
                Toggle(Messages.AppWorldDataPackSearchView.planText4.localized, isOn: $includePreviews).disabled(resolution != nil)
                if filtered.isEmpty { Text(Messages.AppWorldDataPackSearchView.planText5.localized).foregroundStyle(.secondary) }
                else { Picker(Messages.AppWorldDataPackSearchView.planText6.localized, selection: $selectedID) { ForEach(filtered) { Text($0.version_number).tag(Optional($0.id)) } }.disabled(resolution != nil) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Link(Messages.AppWorldDataPackSearchView.errorText7.localized, destination: URL(string: "https://modrinth.com/datapack")!.appendingPathComponent(project.slug))
                Spacer()
                Button(Messages.Common.cancel.localized) { resolution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(plan == nil ? Messages.AppWorldDataPackSearchView.errorText8.localized : Messages.AppWorldDataPackSearchView.errorText9.localized) { advance() }.buttonStyle(.borderedProminent)
                    .disabled(loading || resolution != nil || selectedID == nil || model.busy || model.isInstanceInUse(instance.id))
            }
        }.padding(24).frame(width: 600).interactiveDismissDisabled(model.busy)
        .onDisappear { resolution?.cancel() }
        .onChange(of: includePreviews) { selectedID = filtered.first?.id }
        .task {
            do { versions = try await WorldDataPackDownloads().versions(project: project.id, game: instance.gameVersion); selectedID = filtered.first?.id }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
    private func advance() {
        error = nil
        if let plan {
            model.perform(Messages.AppWorldDataPackSearchView.planText7(String(describing: project.title)), presentErrors: false, instanceID: instance.id) { id in
                do {
                    try await WorldDataPackDownloads().install(plan, instance: instance, folder: world.folder, paths: model.paths, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                    model.notice = Messages.AppWorldDataPackSearchView.planText8(String(describing: world.name)).localized; dismiss()
                } catch { self.error = error.localizedDescription; throw error }
            }
        } else if let version = filtered.first(where: { $0.id == selectedID }) {
            resolution = Task {
                defer { resolution = nil }
                do { let value = try await WorldDataPackDownloads().prepare(version, game: instance.gameVersion); try Task.checkCancellation(); plan = value }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }
    }
}
