import SwiftUI
import AppKit
import RuriCore

struct InstanceCopyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var name: String
    @State private var directoryID: UUID
    @State private var includeWorlds = true
    @State private var includeBackups = false
    @State private var checking = false
    @State private var cancelling = false
    @State private var preview: InstanceCopyPreview?
    @State private var recovery: InstanceCopyRecovery?
    @State private var issue: String?
    @State private var refresh = UUID()
    init(instance: GameInstance) {
        self.instance = instance; _name = State(initialValue: instance.name + " 副本")
        _directoryID = State(initialValue: instance.directoryID ?? GameDirectory.defaultID)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: recovery == nil ? "复制实例" : "恢复实例复制", subtitle: instance.name)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recovery {
                        Label(recovery.committed ? "副本已登记，等待校验和清理" : "复制尚未完成，原实例及其文件保留", systemImage: "arrow.counterclockwise").font(.headline)
                        Text("目标：\(recovery.destination.path)").font(.caption).textSelection(.enabled)
                        Text(recovery.committed ? "核对副本后清理工作记录；发现文件缺失或变化时会保留工作副本，便于检查。" : "恢复会收回本次发布的文件并保留工作副本，随后可以重新复制。").font(.callout).foregroundStyle(.secondary)
                        Button("在 Finder 中查看工作区", systemImage: "folder") { NSWorkspace.shared.open(recovery.workspace) }
                    } else {
                        TextField("副本名称", text: $name).textFieldStyle(.roundedBorder).disabled(model.busy)
                        Picker("保存到", selection: $directoryID) {
                            Text("默认实例文件夹").tag(GameDirectory.defaultID)
                            ForEach(model.state.gameDirectories ?? []) { Text($0.name).tag($0.id) }
                        }.disabled(model.busy)
                        Button("添加目标文件夹…", systemImage: "folder.badge.plus") { addDirectory() }.disabled(model.busy || checking)
                        Toggle("复制存档", isOn: $includeWorlds).disabled(model.busy)
                        Toggle("复制存档备份", isOn: $includeBackups).disabled(model.busy)
                        Text(instance.importedInstallation == nil
                             ? "副本使用独立游戏目录，保留版本、模组与启动设置。Java 和公共游戏资源继续共用；游玩时长与运行历史从零开始。"
                             : "副本使用独立游戏目录，保留本地游戏文件、依赖、模组与启动设置。Java 继续共用；游玩时长与运行历史从零开始。")
                            .font(.callout).foregroundStyle(.secondary)
                        if let preview {
                            Divider()
                            LabeledContent("文件", value: "\(preview.fileCount) 个 · " + ByteCountFormatter.string(fromByteCount: preview.bytes, countStyle: .file))
                            Text("目标：\(preview.destination.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            if !preview.source.installed { Text("源实例尚未安装，副本也会保持待安装状态。").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if checking { ProgressView("正在检查实例与文件…") }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if model.busy { ProgressView(cancelling ? "正在取消并保留工作副本…" : model.activeActivity?.progress.stage ?? "正在处理实例…").controlSize(.small) }
            HStack {
                Button("刷新预览", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(checking || model.busy)
                Spacer()
                Button(model.busy ? "取消复制" : "关闭") {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
                if let recovery {
                    Button(recovery.committed ? "校验并完成复制" : "恢复并保留副本") { model.recoverInstanceCopy(recovery) }.buttonStyle(.borderedProminent).disabled(checking || model.busy)
                } else {
                    Button("创建副本") { if let preview { model.copyInstance(preview) { dismiss() } } }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
                }
            }
        }.padding(24).frame(width: 640, height: 535)
        .interactiveDismissDisabled(model.busy)
        .task(id: name + directoryID.uuidString + String(includeWorlds) + String(includeBackups) + refresh.uuidString) {
            preview = nil; recovery = nil; issue = nil; checking = true
            do {
                try await Task.sleep(for: .milliseconds(250))
                let service = InstanceCopier(paths: model.paths)
                if let pending = try await service.pending(instanceID: instance.id) { try Task.checkCancellation(); recovery = pending }
                else {
                    let result = try await service.preview(instanceID: instance.id, name: name, directoryID: directoryID, options: .init(includeWorlds: includeWorlds, includeBackups: includeBackups))
                    try Task.checkCancellation(); preview = result
                }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
    }
    private func addDirectory() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "选择空文件夹保存实例，也可以在这里新建文件夹。"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.changeDirectory { try GameDirectoryStore.add(name: String(url.lastPathComponent.prefix(100)), url: url, paths: $0) }
            if let added = model.state.gameDirectories?.first(where: { $0.url.standardizedFileURL.path == url.standardizedFileURL.resolvingSymlinksInPath().path }) { directoryID = added.id }
        }
    }
}
