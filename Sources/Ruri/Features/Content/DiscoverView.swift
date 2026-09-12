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
    var author: String { switch self { case .modrinth(let p): p.author; case .curseforge(let p): p.authors?.map(\.name).joined(separator: ", ") ?? "社区作者" } }
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
                            Label("连接 CurseForge", systemImage: "key").font(.headline)
                            Text("配置 Ruri 的 CurseForge API Key 后，即可搜索内容、解析依赖与安装整合包。").foregroundStyle(.secondary)
                            Button("前往设置") { model.page = .settings }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    if loading { ProgressView("正在发现内容…").frame(maxWidth: .infinity).padding(30) }
                    if let error { Surface { VStack(alignment: .leading, spacing: 12) { Text(error).foregroundStyle(.secondary); Button("重试") { retry += 1 } }.frame(maxWidth: .infinity, alignment: .leading) } }
                    if !loading, results.isEmpty, error == nil { EmptyPanel(symbol: "magnifyingglass", title: "没有找到匹配内容", detail: "试试英文名称，或使用更短的关键词。") }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                        ForEach(results) { project in
                            Button { selected = project } label: { projectCard(project) }.buttonStyle(.plain)
                        }
                    }
                    if total > 0 {
                        HStack {
                            Text("\(offset + 1)–\(offset + results.count) / \(total) · \(source.rawValue)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("上一页") { offset = max(0, offset - 20) }.disabled(offset == 0 || loading)
                            Button("下一页") { offset += 20 }.disabled(offset + 20 >= total || loading)
                        }
                    }
                }
            }.padding(28)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "搜索模组、整合包、光影…")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.chooseInstanceImport() } label: { Label("导入整合包", systemImage: "square.and.arrow.down") }.help("导入本地整合包…").disabled(model.busy)
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
                    VStack(alignment: .leading, spacing: 5) { Text(project.title).font(.headline).lineLimit(1); Text("by \(project.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer()
                }
                Text(project.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).frame(height: 49, alignment: .topLeading).multilineTextAlignment(.leading)
                HStack { Label(project.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.accent) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var sourcePicker: some View {
        Picker("内容来源", selection: $source) { ForEach(CatalogSource.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden().help("内容来源")
    }
    private var contentPicker: some View {
        Picker("内容类型", selection: $type) { Text("整合包").tag("modpack"); Text("模组").tag("mod"); Text("资源包").tag("resourcepack"); Text("光影").tag("shader") }.pickerStyle(.segmented)
    }
}
