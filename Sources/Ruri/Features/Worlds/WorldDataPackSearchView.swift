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
                SectionHeading(title: "查找数据包", subtitle: world.name + " · Minecraft " + instance.gameVersion + " · Modrinth")
                Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("搜索数据包名称", text: $query).textFieldStyle(.roundedBorder).onChange(of: query) { offset = 0 }
            if let error { Text(error).foregroundStyle(.orange) }
            if loading { ProgressView("查找兼容数据包…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if projects.isEmpty { EmptyPanel(symbol: "magnifyingglass", title: "没有找到匹配的数据包", detail: "试试英文名称，或使用更短的关键词。") }
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
                Text("\(total) 个结果").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("上一页") { offset = max(0, offset - 20) }.disabled(loading || offset == 0)
                Button("下一页") { offset += 20 }.disabled(loading || offset + 20 >= total)
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
            SectionHeading(title: project.title, subtitle: "安装到 “\(world.name)” · Minecraft \(instance.gameVersion)")
            if loading || resolution != nil { ProgressView(loading ? "获取版本…" : "解析必需依赖…") }
            if let plan {
                Text("共 \(plan.files.count) 个数据包 · \(ByteCountFormatter.string(fromByteCount: plan.downloadSize, countStyle: .file))").foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(plan.versions) { version in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(version.name).font(.headline)
                                Text(version.version_number + (version.project_id == project.id ? "" : " · 必需依赖")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 240)
                Text("安装后启用，下次进入世界时生效。已有同名文件会保留，并提示先处理冲突。").font(.caption).foregroundStyle(.secondary)
            } else if !loading {
                Toggle("显示 Beta / Alpha 版本", isOn: $includePreviews).disabled(resolution != nil)
                if filtered.isEmpty { Text("没有兼容版本。").foregroundStyle(.secondary) }
                else { Picker("版本", selection: $selectedID) { ForEach(filtered) { Text($0.version_number).tag(Optional($0.id)) } }.disabled(resolution != nil) }
            }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                Link("在 Modrinth 查看", destination: URL(string: "https://modrinth.com/datapack")!.appendingPathComponent(project.slug))
                Spacer()
                Button("取消") { resolution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button(plan == nil ? "查看安装清单" : "安装") { advance() }.buttonStyle(.borderedProminent)
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
            model.perform("安装数据包 \(project.title)", presentErrors: false, instanceID: instance.id) { id in
                do {
                    try await WorldDataPackDownloads().install(plan, instance: instance, folder: world.folder, paths: model.paths, downloader: model.installer.downloader) { p in await model.progress(id, p) }
                    model.notice = "数据包已安装到 “\(world.name)”"; dismiss()
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
