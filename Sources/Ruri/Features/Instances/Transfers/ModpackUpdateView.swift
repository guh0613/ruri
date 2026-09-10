import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct ModpackUpdateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var pack: InstalledModpack?
    @State private var releases: [ModpackRelease] = []
    @State private var nextOffset: Int?
    @State private var loading = false
    @State private var includePrereleases = false
    @State private var error: String?
    @State private var prepared: PreparedInstanceImport?
    @State private var plan: PreparedModpackUpdate?
    @State private var keeping = Set<String>()
    private var current: GameInstance { model.state.instances.first { $0.id == instance.id } ?? instance }
    private var pending: Bool { ModpackUpdateStore.hasPending(paths: model.paths, instanceID: instance.id) }
    private var backup: Bool { ModpackUpdateStore.hasBackup(paths: model.paths, instanceID: instance.id) }
    private var displayed: [ModpackRelease] { releases.filter { includePrereleases || $0.stable } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "整合包更新", subtitle: current.name)
            if let pack { Text("\(pack.name) · \(pack.version) · \(pack.format)").font(.callout).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if model.busy { ProgressView("正在处理整合包…").controlSize(.small) }
            if pending {
                Text("上次更新尚未完成。恢复后会保留已成功提交的版本，或还原更新前的文件。")
                Button("恢复未完成的更新") { model.recoverModpackUpdate(current) { reload() } }.disabled(model.busy)
            } else if let plan {
                preview(plan)
            } else if pack != nil {
                HStack {
                    Button("选择更新文件…", systemImage: "doc.badge.arrow.up") { chooseFile() }.disabled(model.busy)
                    Spacer()
                    Toggle("显示测试版", isOn: $includePrereleases).toggleStyle(.checkbox)
                    Button("检查版本") { Task { await loadVersions() } }.disabled(model.busy || loading)
                }
                if loading { ProgressView("正在获取版本列表…").controlSize(.small) }
                if displayed.isEmpty && !loading {
                    ContentUnavailableView("暂无可显示的在线版本", systemImage: "shippingbox", description: Text("可选择下载好的 Modrinth、CurseForge、HMCL 或 MCBBS 整合包文件。"))
                } else {
                    List(displayed) { release in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(release.title).font(.headline)
                                Text(release.gameVersions.joined(separator: "、")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if let date = release.publishedAt { Text(String(date.prefix(10))).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if release.id == pack?.origin?.versionID { Text("当前版本").font(.caption).foregroundStyle(.secondary) }
                            else {
                                if let page = release.page, release.requiresManualDownload { Link("下载页面", destination: page) }
                                Button(release.requiresManualDownload ? "选择已下载文件…" : "选择此版本") { select(release) }.disabled(model.busy)
                            }
                        }.padding(.vertical, 5)
                    }.listStyle(.bordered)
                }
                if let nextOffset { Button("更多版本") { Task { await loadVersions(offset: nextOffset) } }.disabled(loading || model.busy) }
                if backup {
                    Divider()
                    Text("回退只恢复上次更新改动的文件；更新后再次修改的游戏文件会保留。").font(.caption).foregroundStyle(.secondary)
                    Button("回退上次更新", systemImage: "arrow.uturn.backward") { model.rollbackModpack(current) { reload() } }.disabled(model.busy)
                }
            } else {
                Text("此实例没有整合包原始文件记录，暂时无法安全区分包文件与个人文件。").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack { Spacer(); Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy) }
        }.padding(24).frame(width: 680, height: 650).interactiveDismissDisabled(model.busy)
        .task { reload(); await loadVersions() }
        .sheet(item: $prepared) { value in
            ImportInstanceView(prepared: value, updateTarget: current, onPreparedUpdate: { incoming in
                prepared = nil; plan = incoming; keeping = Set(incoming.changes.filter { $0.action == .keep }.map(\.id))
            }, onCancel: {
                prepared = nil; Task { await InstanceTransfer(paths: model.paths).discard(value) }
            })
        }
        .onDisappear {
            if let plan { Task { await ModpackUpdater(paths: model.paths).discard(plan) } }
        }
    }
    @ViewBuilder private func preview(_ plan: PreparedModpackUpdate) -> some View {
        Text("\(plan.current.version) → \(plan.incoming.version)").font(.headline)
        Text("Minecraft \(plan.instance.gameVersion) → \(plan.incoming.settings.gameVersion) · \(plan.incoming.settings.loader.title) \(plan.incoming.settings.loaderVersion ?? "")").font(.callout)
        Text("存档和个人新增文件保留；本地改过的配置默认保留，可逐项选择。成功后可回退上次更新。").font(.caption).foregroundStyle(.secondary)
        if plan.instance.gameVersion != plan.incoming.settings.gameVersion {
            Text("Minecraft 版本将变化；回退更新不会回退存档，请在进入新版世界前按需备份。").font(.caption).foregroundStyle(.secondary)
        }
        List(plan.changes) { change in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.id).font(.system(.callout, design: .monospaced)).lineLimit(2)
                    if let explanation = change.explanation { Text(explanation).font(.caption).foregroundStyle(change.conflict ? .orange : .secondary) }
                }
                Spacer()
                if change.conflict {
                    Toggle("保留本地", isOn: Binding(get: { keeping.contains(change.id) }, set: { if $0 { keeping.insert(change.id) } else { keeping.remove(change.id) } })).toggleStyle(.checkbox)
                } else { Text(change.action.title).font(.caption).foregroundStyle(.secondary) }
            }.padding(.vertical, 3)
        }.listStyle(.bordered)
        HStack {
            Button("重新选择版本") { Task { await ModpackUpdater(paths: model.paths).discard(plan) }; self.plan = nil }.disabled(model.busy)
            Spacer()
            Text("应用 \(plan.changes.filter { !keeping.contains($0.id) }.count) 项文件变更").font(.caption).foregroundStyle(.secondary)
            Button("应用更新") { model.applyModpackUpdate(plan, keeping: keeping) { self.plan = nil; reload() } }.buttonStyle(.borderedProminent).disabled(model.busy)
        }
    }
    private func reload() {
        do { pack = try ModpackRegistry.load(paths: model.paths, instanceID: instance.id); error = nil }
        catch { self.error = error.localizedDescription }
    }
    private func loadVersions(offset: Int = 0) async {
        guard let pack, !pending else { return }
        loading = true; error = nil
        defer { loading = false }
        do {
            let key = pack.origin?.provider == .curseforge ? try CurseForgeKeyStore.load() : ""
            let result = try await ModpackReleaseService().versions(for: pack, curseForgeKey: key, offset: offset)
            try Task.checkCancellation()
            releases = offset == 0 ? result.items : releases + result.items.filter { incoming in !releases.contains { $0.id == incoming.id } }
            nextOffset = result.nextOffset
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip, UTType(filenameExtension: "mrpack") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.perform("读取整合包更新") { _ in prepared = try await InstanceTransfer(paths: model.paths).prepare(url) }
    }
    private func select(_ release: ModpackRelease) {
        var manual: URL?
        if release.requiresManualDownload {
            let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.zip]
            guard panel.runModal() == .OK else { return }; manual = panel.url
        }
        let selectedFile = manual
        model.perform("下载整合包版本") { id in
            let downloader = await model.installer.downloader
            prepared = try await ModpackReleaseService().prepare(release, manualFile: selectedFile, paths: model.paths, downloader: downloader) { p in await model.progress(id, p) }
        }
    }
}
