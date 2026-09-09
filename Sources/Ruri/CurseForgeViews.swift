import SwiftUI
import AppKit
import RuriCore

struct CurseForgeSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var error: String?
    var body: some View {
        Section("CurseForge") {
            LabeledContent("API Key", value: model.curseForgeConfigured ? "已保存在钥匙串" : "尚未配置")
            SecureField(model.curseForgeConfigured ? "输入新 Key 以替换" : "输入 API Key", text: $key)
            HStack {
                Button("保存到钥匙串") {
                    do { try CurseForgeKeyStore.save(key); key = ""; error = nil; model.curseForgeConfigured = true }
                    catch { self.error = error.localizedDescription }
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.curseForgeConfigured {
                    Button("移除 Key") {
                        do { try CurseForgeKeyStore.remove(); key = ""; error = nil; model.curseForgeConfigured = false }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Text("用于 CurseForge 内容搜索、整合包下载与更新。Key 保存在 macOS 钥匙串中，实例导出不包含它。").font(.caption).foregroundStyle(.secondary)
            Link("CurseForge 第三方 API 申请说明", destination: URL(string: "https://support.curseforge.com/support/solutions/articles/9000208346")!)
        }
    }
}

/// Local files are copied into the resumable cache after verification, so a
/// dismissed file panel never leaves a security-scoped URL in a future task.
struct CurseForgeFileRow: View {
    @Environment(AppModel.self) private var model
    let file: CurseForgeFile
    let title: String
    let page: URL
    let manual: Bool
    @Binding var selectedURL: URL?
    @State private var checking = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(file.fileName).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: file.fileLength, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if manual {
                    if checking { ProgressView().controlSize(.small) }
                    else if selectedURL != nil { Label("已校验", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent) }
                    else { TagPill(text: "手动下载") }
                } else { Label("自动下载", systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
            }
            if manual {
                HStack { Link("打开下载页面", destination: page); Spacer(); Button(selectedURL == nil ? "选择已下载文件…" : "重新选择…") { choose() }.disabled(checking) }.font(.callout)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .task(id: file.id) {
            if manual, selectedURL == nil, let cached = await CurseForgeService.cachedFile(file, paths: model.paths), !Task.isCancelled { selectedURL = cached }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "选择 \(file.fileName)。Ruri 会核对版本、大小与校验值。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        checking = true; error = nil
        Task {
            do {
                let cached = try await CurseForgeService.cacheManualFile(url, file: file, paths: model.paths)
                selectedURL = cached
            } catch { self.error = error.localizedDescription }
            checking = false
        }
    }
}

struct CurseForgePlanFiles: View {
    let files: [PlannedCurseFile]
    @Binding var manualFiles: [Int: URL]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if files.contains(where: \.requiresManualDownload) {
                Text("部分作者要求从 CurseForge 页面下载。下载对应版本后选择文件，校验通过即可继续安装。").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(files) { item in
                CurseForgeFileRow(file: item.file, title: item.project.name, page: item.pageURL, manual: item.requiresManualDownload,
                                  selectedURL: Binding(get: { manualFiles[item.id] }, set: { manualFiles[item.id] = $0 }))
            }
        }
    }
}

struct CurseForgeInstallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: CurseForgeProject
    @State private var versions: [CurseForgeFile] = []
    @State private var selectedID: Int?
    @State private var instanceID: UUID?
    @State private var offset = 0
    @State private var total = 0
    @State private var loading = false
    @State private var resolving = false
    @State private var error: String?
    @State private var plan: CurseForgeContentPlan?
    @State private var manualFiles: [Int: URL] = [:]
    @State private var resolution: Task<Void, Never>?
    private var instance: GameInstance? { model.state.instances.first { $0.id == instanceID } }
    private var isPack: Bool { project.contentType == "modpack" }
    private var selected: CurseForgeFile? { versions.first { $0.id == selectedID } }
    private var packIsManual: Bool { project.allowModDistribution == false || selected?.downloadURL == nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: project.name, subtitle: "CurseForge · \(project.authors?.map(\.name).joined(separator: ", ") ?? "社区创作")")
            if let plan {
                Text("将为 \(plan.instance.name) 安装 \(plan.files.count) 个文件，包含必需依赖。").foregroundStyle(.secondary)
                ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(maxHeight: 360)
            } else {
                Text(project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                if !isPack {
                    Picker("安装到实例", selection: $instanceID) {
                        Text("选择实例").tag(nil as UUID?)
                        ForEach(model.state.instances.filter { $0.installed && (project.contentType != "mod" || $0.loader != .vanilla) }) { Text($0.name + " · " + $0.subtitle).tag(Optional($0.id)) }
                    }.disabled(resolving)
                }
                if loading { ProgressView("查找兼容版本…") }
                else if !versions.isEmpty {
                    Picker("内容版本", selection: $selectedID) { ForEach(versions) { Text($0.displayName + ($0.releaseType == 2 ? " · Beta" : $0.releaseType == 3 ? " · Alpha" : "")).tag(Optional($0.id)) } }.disabled(resolving)
                } else { Text(isPack || instance != nil ? "这一页没有兼容版本。" : "请先选择已安装的实例；模组需要相应加载器。").foregroundStyle(.secondary) }
                if total > 50 {
                    HStack { Button("上一页") { offset = max(0, offset - 50) }.disabled(offset == 0 || loading || resolving); Text("第 \(offset / 50 + 1) 页").font(.caption); Button("下一页") { offset += 50 }.disabled(offset + 50 >= total || loading || resolving) }
                }
                if isPack, let file = selected, packIsManual {
                    CurseForgeFileRow(file: file, title: "整合包清单", page: project.page(for: file.id), manual: true, selectedURL: Binding(get: { manualFiles[file.id] }, set: { manualFiles[file.id] = $0 }))
                }
                if project.contentType == "shader" { Text("光影文件放入 shaderpacks；实例需要安装 Iris 或其他兼容光影加载模组。").font(.caption).foregroundStyle(.secondary) }
            }
            if resolving { ProgressView("正在解析必需依赖…") }
            if let error { Text(error).font(.callout).foregroundStyle(.orange) }
            HStack {
                if plan != nil { Button("返回") { plan = nil } }
                Spacer(); Button("取消") { resolution?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(plan == nil ? (isPack ? "读取整合包" : "查看安装清单") : "安装") { advance() }.buttonStyle(.borderedProminent).disabled(!canContinue)
            }
        }.padding(26).frame(width: 570).interactiveDismissDisabled(resolving)
        .onAppear { instanceID = model.selected.flatMap { project.contentType == "mod" && $0.loader == .vanilla ? nil : $0.id } }
        .onChange(of: instanceID) { offset = 0 }
        .onDisappear { resolution?.cancel() }
        .task(id: "\(instanceID?.uuidString ?? "pack"):\(offset)") {
            versions = []; selectedID = nil; total = 0; error = nil
            guard isPack || instance != nil else { return }
            loading = true
            do {
                let page = try await CurseForgeService(apiKey: CurseForgeKeyStore.load()).files(project: project.id, game: isPack ? nil : instance?.gameVersion, loader: project.contentType == "mod" ? instance?.loader : nil, offset: offset)
                try Task.checkCancellation()
                versions = page.data.filter { file in
                    guard file.modId == project.id, file.isAvailable != false else { return false }
                    if isPack { return true }
                    guard let instance, let kind = project.contentType.flatMap(ContentKind.init(rawValue:)) else { return false }
                    return file.supports(instance, kind: kind)
                }
                total = page.pagination?.totalCount ?? page.data.count; selectedID = versions.first?.id; loading = false
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; loading = false } }
        }
    }
    private var canContinue: Bool {
        guard !loading, !resolving, !model.busy else { return false }
        if let plan { return !model.isInstanceInUse(plan.instance.id) && plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil } }
        guard let selected else { return false }
        return isPack ? (!packIsManual || manualFiles[selected.id] != nil) : instance != nil && !model.isInstanceInUse(instanceID)
    }
    private func advance() {
        if let plan { model.installCurseForge(plan, manualFiles: manualFiles); dismiss(); return }
        guard let file = selected else { return }
        if isPack { model.readCurseForgePack(project, file: file, manual: manualFiles[file.id]); dismiss(); return }
        guard let instance else { return }
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

struct CurseForgePlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: CurseForgeContentPlan
    @State private var manualFiles: [Int: URL] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "更新 \(plan.title)", subtitle: "\(plan.instance.name) · \(plan.files.count) 个文件，包含必需依赖")
            ScrollView { CurseForgePlanFiles(files: plan.files, manualFiles: $manualFiles) }.frame(maxHeight: 360)
            HStack { Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("更新") { model.installCurseForge(plan, manualFiles: manualFiles); dismiss() }.buttonStyle(.borderedProminent).disabled(model.busy || model.isInstanceInUse(plan.instance.id) || !plan.manualFiles.allSatisfy { manualFiles[$0.id] != nil }) }
        }.padding(26).frame(width: 570)
    }
}

extension AppModel {
    func installCurseForge(_ plan: CurseForgeContentPlan, manualFiles: [Int: URL]) {
        guard !isInstanceInUse(plan.instance.id) else { return }
        perform("安装 \(plan.title)", instanceID: plan.instance.id) { [self] id in
            try await CurseForgeService(apiKey: "").install(plan, paths: paths, downloader: installer.downloader, manualFiles: manualFiles) { [weak self] p in await self?.progress(id, p) }
            notice = "\(plan.title) 已安装"
        }
    }
    func readCurseForgePack(_ project: CurseForgeProject, file: CurseForgeFile, manual: URL?) {
        perform("读取 \(project.name)") { [self] id in
            let archive: URL
            if let manual { archive = manual }
            else {
                guard project.allowModDistribution != false, let url = file.downloadURL else { throw RuriError.message("此整合包需要先从 CurseForge 页面下载。") }
                archive = try LauncherPaths.safePath("curseforge/\(file.id)/\(file.fileName)", within: paths.cache)
                try await installer.downloader.fetch(file.downloadItem(to: archive, permittedURL: url))
            }
            guard DownloadManager.valid(archive, item: try file.downloadItem(to: archive, permittedURL: nil)) else { throw RuriError.message("整合包校验失败") }
            importingInstance = try await InstanceTransfer(paths: paths).prepare(archive, origin: ModpackOrigin(provider: .curseforge, projectID: String(project.id), versionID: String(file.id))) { [weak self] p in Task { @MainActor in self?.progress(id, p) } }
        }
    }
}
