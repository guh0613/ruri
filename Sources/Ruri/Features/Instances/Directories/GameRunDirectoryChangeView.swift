import SwiftUI
import AppKit
import RuriCore

struct GameRunDirectoryChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var target: GameRunDirectory
    @State private var customDirectory: CustomRunDirectory?
    @State private var chosenURL: URL?
    @State private var selectionRequest = UUID()
    @State private var registering = false
    @State private var preview: GameRunDirectoryChangePreview?
    @State private var recovery: RunDirectoryCopyRecovery?
    @State private var copyFiles = false
    @State private var choiceFor: String?
    @State private var cancelling = false
    @State private var loading = false
    @State private var issue: String?
    @State private var refresh = UUID()
    init(instance: GameInstance) {
        self.instance = instance
        _target = State(initialValue: (instance.runDirectory ?? .isolated) == .isolated ? .shared : .isolated)
        _customDirectory = State(initialValue: instance.customRunDirectory)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: recovery == nil ? "切换运行目录" : "恢复目录复制", subtitle: recovery?.owner.instanceName ?? (instance.name + " · " + instance.subtitle))
            if recovery == nil {
                Picker("目标", selection: $target) { ForEach(GameRunDirectory.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.busy || registering)
                Text(target.explanation).font(.callout).foregroundStyle(.secondary)
                if target == .custom {
                    HStack {
                        Text(customDirectory?.url.path ?? "尚未选择文件夹").font(.caption).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("选择文件夹…") {
                            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
                            panel.message = "选择保存模组、存档和游戏设置的位置。Ruri 会保存目录身份信息，用于识别移动和重新连接的磁盘。"
                            if panel.runModal() == .OK, let url = panel.url { chosenURL = url; selectionRequest = UUID() }
                        }.disabled(model.busy || registering)
                    }
                }
            }
            if loading || registering { ProgressView(registering ? "正在准备所选目录…" : "正在检查目录与文件…").frame(maxWidth: .infinity, minHeight: 220) }
            else if let recovery {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(recovery.committed ? "复制已提交，等待清理记录" : "上次复制尚未完成", systemImage: "arrow.counterclockwise.circle").font(.headline)
                        Text(recovery.committed ? "目标内容和目录设置已生效。恢复只清理本次复制的占用记录，保留已经复制的文件。" : "原目录和原设置仍保留。恢复会收回本次发布的文件，并将工作副本另存，供你检查或删除；外部替换的文件不会被覆盖。")
                        Text("开始于 \(recovery.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        Text("原目录：\(recovery.source.path)\n目标目录：\(recovery.target.path)").font(.caption).textSelection(.enabled)
                        Button("在 Finder 中查看工作区") { NSWorkspace.shared.open(recovery.workspace) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
                }
            }
            else if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("内容处理", selection: $copyFiles) {
                            Text("使用目标已有的内容").tag(false)
                            Text("复制当前内容到空目标").tag(true).disabled(!preview.canCopyToTarget)
                        }.pickerStyle(.radioGroup).disabled(model.busy)
                        if let issue = preview.copyIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                        else if !preview.canCopyToTarget { Text("目标已有文件或备份，不能用复制覆盖。").font(.caption).foregroundStyle(.secondary) }
                        location("原目录", url: preview.source, files: preview.sourceFileCount, bytes: preview.sourceBytes)
                        location("目标目录", url: preview.target, files: preview.targetFileCount, bytes: preview.targetBytes)
                        if !preview.otherInstances.isEmpty {
                            Text("共用目标目录：" + preview.otherInstances.joined(separator: "、")).font(.callout).foregroundStyle(.secondary)
                        }
                        Text(copyFiles ? "先复制游戏文件、模组来源记录和世界备份，再切换目录。原目录仍保留；取消或中断时可恢复并保留工作副本。" : preview.targetFileCount == 0 ? "目标当前为空，游戏会在这里创建新的存档和配置。原目录中的文件和备份会保留，可再次切回。" : "切换后使用目标目录已有的模组、存档、游戏设置和备份。原目录中的文件会保留，可再次切回。")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("文件统计包含该目录对应的内容来源记录和世界备份。").font(.caption).foregroundStyle(.secondary)
                        if instance.repositoryVersionID != nil { Text("游戏本体、依赖库和启动器配置留在原位置，不随运行目录复制。").font(.caption).foregroundStyle(.secondary) }
                    }.padding(2)
                }.frame(minHeight: 230)
            } else if let issue {
                VStack(alignment: .leading, spacing: 12) {
                    Label("暂时无法切换", systemImage: "exclamationmark.triangle").font(.headline)
                    Text(issue).font(.callout).textSelection(.enabled)
                    Button("重新检查") { refresh = UUID() }
                }.frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
            }
            HStack {
                Button("刷新预览", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(loading || registering || model.busy)
                Spacer()
                Button(model.busy ? "取消操作" : "关闭") {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling || (model.busy && recovery != nil))
                if let recovery {
                    Button(recovery.committed ? "清理已完成记录" : "恢复并保留副本") { model.recoverGameRunDirectory(recovery) }.buttonStyle(.borderedProminent).disabled(model.busy || loading || registering)
                } else {
                    Button(copyFiles ? "复制并切换" : "使用目标现有内容") { if let preview { model.changeGameRunDirectory(preview, copyFiles: copyFiles) } }
                        .buttonStyle(.borderedProminent).disabled(preview == nil || loading || registering || model.busy)
                }
            }
            if model.busy { ProgressView(cancelling ? "正在取消并保留工作副本…" : model.activeActivity?.progress.stage ?? "正在处理目录…").controlSize(.small) }
        }.padding(24).frame(width: 640, height: 590)
        .interactiveDismissDisabled(model.busy)
        .task(id: selectionRequest) {
            guard let chosenURL else { return }
            registering = true; issue = nil
            let paths = model.paths
            do {
                let selected = try await Task.detached(priority: .userInitiated) { try CustomRunDirectory.register(at: chosenURL, paths: paths) }.value
                try Task.checkCancellation(); customDirectory = selected; refresh = UUID()
            } catch { if !Task.isCancelled { preview = nil; issue = error.localizedDescription } }
            if !Task.isCancelled { registering = false }
        }
        .task(id: target.rawValue + (customDirectory?.url.path ?? "") + refresh.uuidString) {
            preview = nil; recovery = nil; issue = nil; loading = true
            do {
                let service = GameRunDirectoryChange(paths: model.paths)
                if let pending = try await service.pendingCopy(instanceID: instance.id) { try Task.checkCancellation(); recovery = pending }
                else {
                    let result = try await service.preview(instanceID: instance.id, target: target, customDirectory: customDirectory)
                    try Task.checkCancellation(); preview = result
                    let choice = target.rawValue + result.target.path
                    if choiceFor != choice { copyFiles = result.canCopyToTarget && result.sourceFileCount > 0; choiceFor = choice }
                    else if !result.canCopyToTarget { copyFiles = false }
                }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
        .onChange(of: model.paths.game(instance.id)) {
            if model.state.instances.first(where: { $0.id == instance.id })?.runDirectory == target,
               (target != .custom || model.state.instances.first(where: { $0.id == instance.id })?.customRunDirectory?.id == customDirectory?.id),
               !RunDirectoryCopyGuard.hasPending(paths: model.paths, instanceID: instance.id) { dismiss() }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
    }
    private func location(_ title: String, url: URL, files: Int, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("\(files) 个文件 · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))").font(.caption)
            Button("在 Finder 中显示") { NSWorkspace.shared.open(url) }.buttonStyle(.link).disabled(!FileManager.default.fileExists(atPath: url.path))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
