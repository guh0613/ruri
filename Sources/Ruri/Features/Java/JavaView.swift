import SwiftUI
import AppKit
import RuriCore

struct JavaView: View {
    @Environment(AppModel.self) private var model
    @State private var available: [RemoteJava] = []
    @State private var javaError: String?
    @State private var loadingRemote = false
    @State private var removal: JavaRemovalRequest?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionHeading(title: "为游戏选对 Java", subtitle: "自动识别版本与架构，让每个实例使用合适的运行时。")
                    Spacer()
                    Button("添加本机 Java…", systemImage: "plus") { model.chooseJava() }.disabled(model.busy)
                    Button("重新检测", systemImage: "arrow.clockwise") { Task { await model.scanJava() } }.disabled(model.scanningJava || model.busy)
                }
                if model.scanningJava { ProgressView("正在检测本机 Java…") }
                if model.javaEntries.isEmpty && !model.scanningJava { EmptyPanel(symbol: "cup.and.saucer", title: "没有找到 Java", detail: "添加已经安装的 Java，或从下方下载游戏运行时。") }
                ForEach(model.javaEntries) { entry in runtimeRow(entry) }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("下载官方游戏运行时").font(.headline)
                        Text("Minecraft 的 Java 要求以版本清单为准。旧版游戏可能需要 Intel Java 和 Rosetta；较新版本优先使用 Apple Silicon 原生运行时。").font(.callout).foregroundStyle(.secondary)
                        if loadingRemote { ProgressView("获取 Mojang 运行时列表…").controlSize(.small) }
                        if let javaError { Text(javaError).font(.caption).foregroundStyle(.orange) }
                        ForEach(available) { runtime in
                            let installed = model.javaEntries.contains { $0.managedID == runtime.id && $0.runtime != nil }
                            let resumable = FileManager.default.fileExists(atPath: model.paths.runtimes.appendingPathComponent(".partial-\(runtime.id)").path)
                            let broken = !installed && FileManager.default.fileExists(atPath: model.paths.runtimes.appendingPathComponent(runtime.id).path)
                            HStack {
                                Text(runtime.label).font(.callout)
                                Spacer()
                                if resumable { Button("清理未完成文件") { requestRemoval(runtime.id, partial: true) }.disabled(model.busy) }
                                Button(installed ? "已安装" : broken ? "修复" : resumable ? "继续安装" : "安装") { model.installJava(runtime, repairing: broken) }.disabled(model.busy || installed)
                            }
                        }
                        HStack { Link("Azul Zulu 下载", destination: AppLinks.azulJavaDownloads); Link("Eclipse Temurin 下载", destination: AppLinks.temurinJavaDownloads) }.font(.callout)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(30)
        }.sheet(item: $removal) { JavaRemovalView(request: $0) }
        .task {
            loadingRemote = true
            do { available = try await JavaInstaller(paths: model.paths).available() } catch { javaError = error.localizedDescription }
            loadingRemote = false
        }
    }
    private func runtimeRow(_ entry: JavaRuntimeEntry) -> some View {
        let remote = entry.remote ?? available.first { $0.id == entry.managedID }
        let runtime = entry.runtime ?? entry.addedRuntime
        return Surface {
            HStack(spacing: 18) {
                Text(runtime.map { String($0.major) } ?? remote.map { String($0.major) } ?? "?")
                    .font(.system(size: 25, weight: .bold, design: .rounded)).foregroundStyle(entry.issue == nil ? Theme.accent : .orange)
                    .frame(width: 54, height: 54).background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(runtime?.label ?? remote?.label ?? "不可用的 Java").font(.headline)
                        TagPill(text: entry.source)
                        if let selected = model.state.settings.defaultLaunchSettings.java.path, JavaDiscovery.sameExecutable(selected, entry.path) { TagPill(text: "默认") }
                    }
                    if let issue = entry.issue { Text(issue).font(.caption).foregroundStyle(.orange) }
                    else if let runtime { Text(runtime.version).font(.caption).foregroundStyle(.secondary) }
                    Text(entry.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                Spacer()
                if let remote { Button("修复") { model.installJava(remote, repairing: true) }.disabled(model.busy) }
                Menu {
                    if entry.runtime != nil { Button("设为默认 Java") { model.defaultJava(entry.path) } }
                    Button("重新选择路径…") { model.chooseJava(replacing: entry.path) }
                    Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
                    if entry.manual { Button("从手动列表移除") { model.forgetJava(entry.path) } }
                    if let id = entry.managedID {
                        Divider(); Button("移到废纸篓…", role: .destructive) { requestRemoval(id) }
                    }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 26).disabled(model.busy)
            }
        }
    }
    private func requestRemoval(_ id: String, partial: Bool = false) {
        let entry = model.javaEntries.first { $0.managedID == id }
        let title = entry?.runtime.map { $0.label + " · " + $0.version } ?? entry?.remote?.label ?? available.first { $0.id == id }?.label ?? id
        do { removal = .init(id: id, title: title, partial: partial, references: try JavaRuntimeStore.references(to: id, paths: model.paths, partial: partial)) }
        catch { javaError = error.localizedDescription }
    }
}

private struct JavaRemovalRequest: Identifiable { let id: String; let title: String; let partial: Bool; let references: [String] }
private struct JavaRemovalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let request: JavaRemovalRequest
    @State private var resetReferences = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(request.partial ? "清理未完成的 Java 下载" : "移除 Ruri 下载的 Java").font(.title2.bold())
            Text(request.title).font(.callout).textSelection(.enabled)
            if !request.references.isEmpty {
                Text("以下设置仍在使用这一路径：").font(.callout)
                ScrollView { VStack(alignment: .leading) { ForEach(Array(request.references.enumerated()), id: \.offset) { _, name in Text(name) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 140)
                Toggle("将这些设置改为自动选择 Java", isOn: $resetReferences)
            }
            Text("文件会移到废纸篓；正在被游戏或安装器使用时无法移除。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("移到废纸篓", role: .destructive) { model.removeJava(request.id, resetReferences: resetReferences, partial: request.partial); dismiss() }
                    .disabled(!request.references.isEmpty && !resetReferences)
            }
        }.padding(24).frame(width: 480)
    }
}
