import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

enum CatalogSource: String, CaseIterable, Identifiable {
    case modrinth = "Modrinth", curseforge = "CurseForge"
    var id: String { rawValue }
}

private enum CatalogProject: Identifiable {
    case modrinth(ModrinthProject), curseforge(CurseForgeProject)
    var id: String { switch self { case .modrinth(let p): "mr:" + p.id; case .curseforge(let p): "cf:\(p.id)" } }
    var title: String { switch self { case .modrinth(let p): p.title; case .curseforge(let p): p.name } }
    var author: String { switch self { case .modrinth(let p): p.author; case .curseforge(let p): p.authors?.map(\.name).joined(separator: ", ") ?? Messages.AppDiscoverView.communityAuthor.localized } }
    var summary: String { switch self { case .modrinth(let p): p.description; case .curseforge(let p): p.summary } }
    var icon: URL? { switch self { case .modrinth(let p): p.icon_url; case .curseforge(let p): p.logo?.thumbnailUrl } }
    var downloads: Double { switch self { case .modrinth(let p): Double(p.downloads); case .curseforge(let p): p.downloadCount } }
}

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var type = "modpack"
    @State private var source = CatalogSource.modrinth
    @State private var results: [CatalogProject] = []
    @State private var loading = false
    @State private var error: String?
    @State private var total = 0
    @State private var offset = 0
    @State private var retry = 0
    @State private var selected: CatalogProject?
    private var queryID: String { "\(source.rawValue):\(type):\(search)" }
    private var missingKey: Bool { source == .curseforge && !model.curseForgeConfigured }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { contentPicker.fixedSize(); Spacer(); sourcePicker.fixedSize() }
                    VStack(alignment: .leading, spacing: 12) { contentPicker; sourcePicker }
                }
                if missingKey {
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Label(Messages.AppDiscoverView.connectCurseForge.localized, systemImage: "key").font(.headline)
                            Text(Messages.AppDiscoverView.curseforgeSetupDetails.localized).foregroundStyle(.secondary)
                            Button(Messages.AppDiscoverView.goToSettings.localized) { model.preferencesPane = .network; model.page = .settings }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if loading { ProgressView(Messages.AppDiscoverView.discoveringContent.localized).frame(maxWidth: .infinity).padding(30) }
                    if let error { Surface { VStack(alignment: .leading, spacing: 12) { Text(error).foregroundStyle(.secondary); Button(Messages.AppDiscoverView.retry.localized) { retry += 1 } }.frame(maxWidth: .infinity, alignment: .leading) } }
                    if !loading, results.isEmpty, error == nil { EmptyPanel(symbol: "magnifyingglass", title: Messages.AppDiscoverView.noMatchingContent.localized, detail: Messages.AppDiscoverView.tryShorterSearch.localized) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(results) { project in
                            Button { selected = project } label: { projectCard(project) }.buttonStyle(.plain)
                        }
                    }
                    if total > 0 {
                        HStack {
                            Text("\(offset + 1)–\(offset + results.count) / \(total) · \(source.rawValue)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(Messages.AppDiscoverView.previousPage.localized) { offset = max(0, offset - 20) }.disabled(offset == 0 || loading)
                            Button(Messages.AppDiscoverView.nextPage.localized) { offset += 20 }.disabled(offset + 20 >= total || loading)
                        }
                    }
                }
            }.padding(28)
        }
        .searchable(text: $search, placement: .toolbar, prompt: Messages.AppDiscoverView.searchContent.localized)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.chooseInstanceImport() } label: { Label(Messages.AppDiscoverView.importModpack.localized, systemImage: "square.and.arrow.down") }.help(Messages.AppDiscoverView.importLocalModpack.localized).disabled(model.busy)
            }
        }
        .onChange(of: queryID) { offset = 0 }
        .task(id: "\(queryID):\(offset):\(retry):\(model.curseForgeConfigured)") {
            results = []; total = 0; loading = !missingKey; error = nil
            guard !missingKey else { return }
            do {
                try await Task.sleep(for: .milliseconds(300))
                if source == .modrinth {
                    let page = try await ModrinthService().search(search, type: type, offset: offset)
                    try Task.checkCancellation(); results = page.hits.map(CatalogProject.modrinth); total = page.total_hits
                } else {
                    let page = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).search(search, type: type, offset: offset)
                    try Task.checkCancellation(); results = page.data.map(CatalogProject.curseforge); total = min(page.pagination?.totalCount ?? page.data.count, 10_000)
                }
                loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
        .sheet(item: $selected) { project in
            switch project { case .modrinth(let p): ContentInstallView(project: p); case .curseforge(let p): CurseForgeInstallView(project: p) }
        }
    }
    private func projectCard(_ project: CatalogProject) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    AsyncImage(url: project.icon) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(12).foregroundStyle(Theme.accent) }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 5) { Text(project.title).font(.headline).lineLimit(1); Text(Messages.AppDiscoverView.authorBy(project.author).localized).font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer()
                }
                Text(project.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).frame(height: 49, alignment: .topLeading).multilineTextAlignment(.leading)
                HStack { Label(LocalizedFormat.compactNumber(project.downloads), systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.accent) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var sourcePicker: some View {
        Picker(Messages.AppDiscoverView.contentSource.localized, selection: $source) { ForEach(CatalogSource.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().help(Messages.AppDiscoverView.contentSource.localized)
    }
    private var contentPicker: some View {
        Picker(Messages.AppDiscoverView.contentType.localized, selection: $type) { Text(Messages.AppDiscoverView.modpacks.localized).tag("modpack"); Text(Messages.AppDiscoverView.mods.localized).tag("mod"); Text(Messages.AppDiscoverView.resourcePacks.localized).tag("resourcepack"); Text(Messages.AppDiscoverView.shaders.localized).tag("shader") }.pickerStyle(.segmented)
    }
}
