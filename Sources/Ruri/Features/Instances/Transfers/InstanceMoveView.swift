import SwiftUI
import AppKit
import RuriCore

struct InstanceMoveView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var directoryID: UUID?
    @State private var preview: InstanceMovePreview?
    @State private var recovery: InstanceMoveRecovery?
    @State private var checking = false
    @State private var cancelling = false
    @State private var issue: String?
    @State private var operationIssue: String?
    @State private var refresh = UUID()
    private var source: GameInstance { model.state.instances.first { $0.id == instance.id } ?? instance }
    private var choices: [UUID] { ([GameDirectory.defaultID] + (model.state.gameDirectories ?? []).map(\.id)).filter { $0 != (source.directoryID ?? GameDirectory.defaultID) } }
    private func directoryName(_ id: UUID) -> String {
        id == GameDirectory.defaultID ? "默认实例文件夹" : model.state.gameDirectories?.first(where: { $0.id == id })?.name ?? "无法访问的文件夹"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: recovery == nil ? "移动实例" : "恢复实例移动", subtitle: source.name)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let recovery {
                        Label(recovery.committed ? "目标实例已登记，等待校验与清理" : "移动尚未完成，原实例仍保留", systemImage: "arrow.counterclockwise").font(.headline)
                        path("原位置", recovery.source)
                        path("目标位置", recovery.destination)
                        Text(recovery.committed ? "校验目标和原文件后继续清理。原文件有变化或希望自行核对时，可以保留原文件完成移动。" : "恢复会收回本次发布的文件，并保留工作副本；原实例可以继续使用。").font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("查看工作区", systemImage: "folder") { reveal(recovery.workspace) }
                            Button("查看原文件", systemImage: "folder") { reveal(recovery.retiredSource ?? recovery.source) }
                            Button("查看目标", systemImage: "folder") { reveal(recovery.destination) }
                        }.disabled(model.busy)
                    } else {
                        LabeledContent("当前文件夹", value: directoryName(source.directoryID ?? GameDirectory.defaultID))
                        Picker("移动到", selection: $directoryID) {
                            if directoryID == nil { Text("选择目标文件夹").tag(UUID?.none) }
                            ForEach(choices, id: \.self) { id in Text(directoryName(id)).tag(Optional(id)) }
                        }.disabled(model.busy)
                        Button("添加目标文件夹…", systemImage: "folder.badge.plus", action: addDirectory).disabled(model.busy || checking)
                        Text("实例名称、收藏、启动设置、游玩时长和运行历史都会保留。Java 和公共资源继续共用。").font(.callout).foregroundStyle(.secondary)
                        switch source.runDirectory ?? .isolated {
                        case .isolated: Text("存档、模组、备份和游戏设置随实例移动；目标校验通过后才会清理原文件。")
                        case .shared: Text("当前共享游戏内容和备份会复制到目标，改为独立运行。原共享目录会保留，供其他实例继续使用。")
                        case .custom: Text("移动实例记录和历史，自定义运行目录中的游戏文件与备份保持原处。")
                        }
                        if let preview {
                            Divider()
                            LabeledContent("移动文件", value: "\(preview.fileCount) 个 · " + ByteCountFormatter.string(fromByteCount: preview.bytes, countStyle: .file))
                            path("目标实例", preview.destination)
                            if let kept = preview.retainedGameDirectory { path("保留的运行目录", kept) }
                            if let prior = preview.preservedPreviousData {
                                Text("以前留下的独立目录内容也会保留在目标实例中。").font(.caption).foregroundStyle(.secondary)
                                path("旧内容", prior)
                            }
                        }
                    }
                    if checking { ProgressView("正在核对实例、运行历史与文件…") }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if let operationIssue { Label(operationIssue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            if model.busy {
                ProgressView(model.activeActivity?.progress.stage ?? "正在移动实例…", value: model.activeActivity?.progress.fraction).controlSize(.small)
                if cancelling { Text("正在结束当前步骤；已提交的移动会保留恢复入口。").font(.caption).foregroundStyle(.secondary) }
            }
            HStack {
                Button("刷新", systemImage: "arrow.clockwise") { operationIssue = nil; refresh = UUID() }.disabled(checking || model.busy)
                Spacer()
                Button(model.busy ? "取消" : "关闭") {
                    if model.busy { cancelling = true; model.operation?.cancel() } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(cancelling)
                if let recovery {
                    if recovery.committed {
                        Menu("完成移动") {
                            Button("校验并清理原文件") { recover(recovery, preserving: false) }
                            Button("保留原文件并完成") { recover(recovery, preserving: true) }
                        } primaryAction: { recover(recovery, preserving: false) }
                        .menuStyle(.borderedButton).fixedSize().disabled(checking || model.busy)
                    } else {
                        Button("恢复并保留副本") { recover(recovery, preserving: false) }.buttonStyle(.borderedProminent).disabled(checking || model.busy)
                    }
                } else {
                    Button("移动实例") {
                        if let preview { operationIssue = nil; model.moveInstance(preview, failed: { operationIssue = $0 }) { dismiss() } }
                    }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
                }
            }
        }.padding(24).frame(width: 660, height: 535)
        .interactiveDismissDisabled(model.busy)
        .onAppear { if directoryID == nil { directoryID = choices.first } }
        .task(id: (directoryID?.uuidString ?? "") + refresh.uuidString) {
            preview = nil; recovery = nil; issue = nil; checking = true
            do {
                try await Task.sleep(for: .milliseconds(200))
                let service = InstanceMover(paths: model.basePaths)
                if let pending = try await service.pending(instanceID: instance.id) { try Task.checkCancellation(); recovery = pending }
                else if let directoryID {
                    let value = try await service.preview(instanceID: instance.id, directoryID: directoryID)
                    try Task.checkCancellation(); preview = value
                } else { issue = "请先添加另一个实例文件夹。" }
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
        .onChange(of: model.busy) { if !model.busy { cancelling = false; refresh = UUID() } }
        .onChange(of: directoryID) { operationIssue = nil }
    }
    private func path(_ label: String, _ url: URL) -> some View { Text("\(label)：\(url.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
    private func reveal(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        else { issue = "此位置暂时无法访问，请连接磁盘后重试：\(url.path)" }
    }
    private func recover(_ pending: InstanceMoveRecovery, preserving: Bool) {
        operationIssue = nil
        model.recoverInstanceMove(pending, preservingSource: preserving, failed: { operationIssue = $0 }) { dismiss() }
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
