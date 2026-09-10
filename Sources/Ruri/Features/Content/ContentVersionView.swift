import SwiftUI
import RuriCore

struct ContentVersionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let record: ManagedContent
    let instanceID: UUID
    @State private var versions: [Choice] = []
    @State private var selectedID: String?
    @State private var includePrereleases = false
    @State private var loading = false
    @State private var resolving = false
    @State private var error: String?
    @State private var offset = 0
    @State private var total = 0
    @State private var plan: CurseForgeContentPlan?
    @State private var manualFiles: [Int: URL] = [:]
    @State private var resolution: Task<Void, Never>?
    private var instance: GameInstance? { model.state.instances.first { $0.id == instanceID } }
    private var choices: [Choice] { versions.filter { includePrereleases || $0.isRelease || $0.id == record.versionID } }
    private var selected: Choice? { choices.first { $0.id == selectedID } }
    private var requestKey: String { "\(instance?.gameVersion ?? ""): \(instance?.loader.rawValue ?? ""): \(offset)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "更换内容版本", subtitle: record.title)
            Text("当前版本：\(record.versionName) · \(instance?.name ?? "实例已移除")")
                .font(.callout).foregroundStyle(.secondary)
            if let plan {
                Text("将安装 \(plan.files.count) 个文件，包含必需依赖。").font(.callout)
                ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(height: 260)
            } else {
                Toggle("包含 Beta / Alpha 测试版", isOn: $includePrereleases).disabled(resolving)
                if loading { ProgressView("查找兼容版本…").frame(maxWidth: .infinity, minHeight: 180) }
                else {
                    List(selection: $selectedID) {
                        ForEach(choices) { choice in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.title).lineLimit(2)
                                    Text(choice.date.prefix(10)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if choice.id == record.versionID { TagPill(text: "已安装") }
                                TagPill(text: choice.channel)
                            }.padding(.vertical, 4).tag(choice.id)
                        }
                    }.frame(height: 230).disabled(resolving)
                    if choices.isEmpty { Text("没有匹配的版本。可查看测试版或其他分页。").font(.caption).foregroundStyle(.secondary) }
                }
                if record.provider == "curseforge", total > 50 {
                    HStack {
                        Button("上一页") { offset = max(0, offset - 50) }.disabled(offset == 0 || loading || resolving)
                        Text("第 \(offset / 50 + 1) 页").font(.caption)
                        Button("下一页") { offset += 50 }.disabled(offset + 50 >= total || loading || resolving)
                    }
                }
                Text("可选择旧版或新版。会按所选版本处理必需依赖，并保留当前启用或停用状态。").font(.caption).foregroundStyle(.secondary)
            }
            if resolving { ProgressView("正在解析必需依赖…") }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            HStack {
                if plan != nil { Button("返回版本列表") { plan = nil; manualFiles = [:] } }
                Spacer()
                Button("取消") { resolution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan != nil || record.provider == "modrinth" ? "安装所选版本" : "查看安装清单", action: install)
                    .buttonStyle(.borderedProminent).disabled(!canInstall)
            }
        }.padding(24).frame(width: 600)
        .task(id: requestKey) { await loadVersions() }
        .onDisappear { resolution?.cancel() }
        .interactiveDismissDisabled(resolving)
    }

    private var canInstall: Bool {
        guard instance != nil, !loading, !resolving, !model.busy, !model.isInstanceInUse(instanceID) else { return false }
        if let plan { return plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil } }
        return selected != nil && selectedID != record.versionID
    }

    private func loadVersions() async {
        resolution?.cancel(); resolving = false; loading = false
        versions = []; selectedID = nil; error = nil; plan = nil; manualFiles = [:]; total = 0
        guard let instance else { return }
        loading = true
        do {
            if record.provider == "modrinth" {
                let result = try await ModrinthService().versions(project: record.projectID, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader.rawValue : nil)
                try Task.checkCancellation()
                versions = result.filter {
                    $0.project_id == record.projectID && $0.game_versions.contains(instance.gameVersion) &&
                    (record.kind != .mod || $0.loaders.contains(instance.loader.rawValue)) && $0.primaryFile != nil
                }.map(Choice.modrinth)
            } else if record.provider == "curseforge", let project = Int(record.projectID) {
                let page = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).files(project: project, game: instance.gameVersion, loader: record.kind == .mod ? instance.loader : nil, offset: offset)
                try Task.checkCancellation()
                versions = page.data.filter { $0.modId == project && $0.isAvailable != false && $0.supports(instance, kind: record.kind) }.map(Choice.curseforge)
                total = page.pagination?.totalCount ?? page.data.count
            } else { throw RuriError.message("此内容没有可查询的版本来源。") }
            var seen = Set<String>(); versions = versions.filter { seen.insert($0.id).inserted }
            if versions.contains(where: { $0.id == record.versionID }) { selectedID = record.versionID }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        if !Task.isCancelled { loading = false }
    }

    private func install() {
        guard canInstall, let instance else { return }
        if let plan { model.installCurseForge(plan, manualFiles: manualFiles); dismiss(); return }
        guard let selected else { return }
        switch selected {
        case .modrinth(let version):
            model.perform("更换 \(record.title) 的版本", instanceID: instanceID) { id in
                try await ModrinthService().install(version: version, type: record.kind.rawValue, instance: instance, paths: model.paths, downloader: model.installer.downloader) { progress in await model.progress(id, progress) }
                model.notice = "\(record.title) 已更换为 \(version.version_number)"
            }
            dismiss()
        case .curseforge(let file):
            resolving = true; error = nil
            resolution = Task {
                do {
                    let result = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).plan(file: file, instance: instance, paths: model.paths)
                    try Task.checkCancellation(); plan = result
                } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                resolving = false
            }
        }
    }

    private enum Choice: Identifiable {
        case modrinth(ModrinthVersion), curseforge(CurseForgeFile)
        var id: String { switch self { case .modrinth(let value): value.id; case .curseforge(let value): String(value.id) } }
        var title: String { switch self { case .modrinth(let value): value.name; case .curseforge(let value): value.displayName } }
        var date: String { switch self { case .modrinth(let value): value.date_published ?? ""; case .curseforge(let value): value.fileDate } }
        var channel: String {
            switch self {
            case .modrinth(let value): value.version_type == "beta" ? "Beta" : value.version_type == "alpha" ? "Alpha" : "正式版"
            case .curseforge(let value): value.releaseType == 2 ? "Beta" : value.releaseType == 3 ? "Alpha" : "正式版"
            }
        }
        var isRelease: Bool { channel == "正式版" }
    }
}
