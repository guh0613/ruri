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
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: "让世界，多一点不同", subtitle: "从 \(source.rawValue) 发现社区创作的内容。")
                    Spacer(); Button("导入整合包…", systemImage: "square.and.arrow.down") { model.chooseInstanceImport() }.disabled(model.busy)
                }
                Picker("内容来源", selection: $source) { ForEach(CatalogSource.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 310)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { searchField.frame(minWidth: 210); contentPicker.frame(width: 310) }
                    VStack(alignment: .leading, spacing: 12) { searchField; contentPicker }
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
            }.padding(30)
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
    private var searchField: some View { TextField("搜索模组、整合包、光影…", text: $search).textFieldStyle(.roundedBorder) }
    private var contentPicker: some View {
        Picker("内容类型", selection: $type) { Text("整合包").tag("modpack"); Text("模组").tag("mod"); Text("资源包").tag("resourcepack"); Text("光影").tag("shader") }.pickerStyle(.segmented)
    }
}

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
                Picker("安装到实例", selection: $instanceID) {
                    Text("选择一个实例").tag(nil as UUID?)
                    ForEach(model.state.instances.filter(\.installed)) { Text($0.name + " · " + $0.subtitle).tag(Optional($0.id)) }
                }
            }
            if loading { ProgressView("查找兼容版本…") }
            else if !versions.isEmpty {
                Picker("内容版本", selection: $selectedVersion) { ForEach(versions) { Text($0.name).tag($0.id) } }
            } else { Text(isPack || instance != nil ? "没有兼容的版本。" : "请先选择已安装的游戏实例。").foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            if project.project_type == "shader" { Text("光影文件会放入 shaderpacks。请确保实例已经安装 Iris 或其他兼容的光影加载模组。").font(.caption).foregroundStyle(.secondary) }
            if project.project_type == "mod" { Text("会自动解析并安装此版本的必需依赖。").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Link("在 Modrinth 查看", destination: URL(string: "https://modrinth.com/\(project.project_type)/\(project.slug)")!)
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isPack ? "查看整合包" : "安装") {
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
                let result = try await service.versions(project: project.id, game: isPack ? nil : instance?.gameVersion, loader: project.project_type == "mod" ? instance?.loader.rawValue : nil)
                try Task.checkCancellation(); versions = result; selectedVersion = result.first?.id ?? ""
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            loading = false
        }
    }
}

extension AppModel {
    func importPack(_ url: URL) {
        guard !busy else { return }
        prepareInstanceImport(url)
    }
    func installContent(project: ModrinthProject, version: ModrinthVersion, instance: GameInstance?) {
        perform("安装 \(project.title)", instanceID: project.project_type == "modpack" ? nil : instance?.id) { [self] id in
            if project.project_type == "modpack" {
                guard let file = version.primaryFile else { throw RuriError.message("该版本没有整合包文件") }
                let archive = paths.cache.appendingPathComponent("pack-\(version.id).mrpack")
                progress(id, InstallProgress("下载整合包清单"))
                try await installer.downloader.fetch(DownloadItem(url: file.url, destination: archive, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
                importingInstance = try await InstanceTransfer(paths: paths).prepare(archive, origin: ModpackOrigin(provider: .modrinth, projectID: project.id, versionID: version.id)) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
                notice = "整合包清单已读取"; return
            } else if let instance {
                try await ModrinthService().install(version: version, type: project.project_type, instance: instance, paths: paths, downloader: installer.downloader) { [weak self] p in await self?.progress(id, p) }
            } else { throw RuriError.message("请选择游戏实例") }
            notice = "\(project.title) 已安装"
        }
        page = .downloads
    }
}
