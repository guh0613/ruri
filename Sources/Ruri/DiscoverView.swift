import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var type = "modpack"
    @State private var results: [ModrinthProject] = []
    @State private var loading = false
    @State private var error: String?
    @State private var total = 0
    @State private var selected: ModrinthProject?
    @State private var showImporter = false
    private let service = ModrinthService()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: "让世界，多一点不同", subtitle: "从 Modrinth 发现社区创作的内容。")
                    Spacer(); Button("导入整合包…", systemImage: "square.and.arrow.down") { showImporter = true }.disabled(model.busy)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) { searchField.frame(minWidth: 210); contentPicker.frame(width: 310) }
                    VStack(alignment: .leading, spacing: 12) { searchField; contentPicker }
                }
                if loading { ProgressView("正在发现内容…").frame(maxWidth: .infinity).padding(30) }
                if let error { Surface { Text(error).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) } }
                if !loading, results.isEmpty, error == nil { EmptyPanel(symbol: "magnifyingglass", title: "没有找到匹配内容", detail: "试试英文名称，或使用更短的关键词。") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(results) { project in
                        Button { selected = project } label: {
                            Surface {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 12) {
                                        AsyncImage(url: project.icon_url) { image in image.resizable().scaledToFit() } placeholder: { Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(12).foregroundStyle(Theme.accent) }.frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 11))
                                        VStack(alignment: .leading, spacing: 5) { Text(project.title).font(.headline).lineLimit(1); Text("by \(project.author)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }; Spacer()
                                    }
                                    Text(project.description).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3).frame(height: 49, alignment: .topLeading).multilineTextAlignment(.leading)
                                    HStack { Label(project.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.accent) }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                if !results.isEmpty { Text("显示 \(results.count) / \(total) 个结果 · 内容由 Modrinth 提供").font(.caption).foregroundStyle(.secondary) }
            }.padding(30)
        }
        .task(id: search + ":" + type) {
            loading = true; error = nil
            do {
                try await Task.sleep(for: .milliseconds(300))
                let result = try await service.search(search, type: type)
                try Task.checkCancellation(); results = result.hits; total = result.total_hits; loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
        .sheet(item: $selected) { project in ContentInstallView(project: project) }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [UTType(filenameExtension: "mrpack") ?? .zip, .zip]) { result in
            switch result { case .success(let url): model.importPack(url); case .failure(let error): model.error = error.localizedDescription }
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
                Button(isPack ? "安装为新实例" : "安装") {
                    guard let version = versions.first(where: { $0.id == selectedVersion }) else { return }
                    model.installContent(project: project, version: version, instance: instance); dismiss()
                }.buttonStyle(.borderedProminent).disabled(loading || selectedVersion.isEmpty || model.busy || (!isPack && (instance == nil || model.runningID == instanceID)))
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
        if url.pathExtension.lowercased() != "mrpack" { prepareInstanceImport(url); return }
        perform("导入 \(url.lastPathComponent)") { [self] id in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let result = try await ModpackImporter(paths: paths).install(url, installer: installer) { [weak self] p in await self?.progress(id, p) }
            state.instances.append(result); select(result); notice = "整合包 \(result.name) 已安装"
        }
        page = .downloads
    }
    func installContent(project: ModrinthProject, version: ModrinthVersion, instance: GameInstance?) {
        perform("安装 \(project.title)") { [self] id in
            if project.project_type == "modpack" {
                guard let file = version.primaryFile else { throw RuriError.message("该版本没有整合包文件") }
                let archive = paths.cache.appendingPathComponent("pack-\(version.id).mrpack")
                progress(id, InstallProgress("下载整合包清单"))
                try await installer.downloader.fetch(DownloadItem(url: file.url, destination: archive, sha1: file.hashes["sha1"], sha512: file.hashes["sha512"], size: file.size))
                let result = try await ModpackImporter(paths: paths).install(archive, installer: installer) { [weak self] p in await self?.progress(id, p) }
                state.instances.append(result); select(result)
            } else if let instance {
                try await ModrinthService().install(version: version, type: project.project_type, instance: instance, paths: paths, downloader: installer.downloader) { [weak self] p in await self?.progress(id, p) }
            } else { throw RuriError.message("请选择游戏实例") }
            notice = "\(project.title) 已安装"
        }
        page = .downloads
    }
}
