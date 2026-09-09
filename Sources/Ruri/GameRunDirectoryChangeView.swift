import SwiftUI
import AppKit
import RuriCore

struct GameRunDirectoryChangeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instance: GameInstance
    @State private var target: GameRunDirectory
    @State private var preview: GameRunDirectoryChangePreview?
    @State private var loading = false
    @State private var issue: String?
    @State private var refresh = UUID()
    init(instance: GameInstance) {
        self.instance = instance
        _target = State(initialValue: (instance.runDirectory ?? .isolated) == .isolated ? .shared : .isolated)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "切换运行目录", subtitle: instance.name + " · " + instance.subtitle)
            Picker("目标", selection: $target) { ForEach(GameRunDirectory.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).disabled(model.busy)
            Text(target.explanation).font(.callout).foregroundStyle(.secondary)
            if loading { ProgressView("正在检查目录与文件…").frame(maxWidth: .infinity, minHeight: 220) }
            else if let preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        location("原目录", url: preview.source, files: preview.sourceFileCount, bytes: preview.sourceBytes)
                        location("目标目录", url: preview.target, files: preview.targetFileCount, bytes: preview.targetBytes)
                        if !preview.otherInstances.isEmpty {
                            Text("共用目标目录：" + preview.otherInstances.joined(separator: "、")).font(.callout).foregroundStyle(.secondary)
                        }
                        Text(preview.targetFileCount == 0 ? "目标当前为空，游戏会在这里创建新的存档和配置。原目录中的文件和备份会保留，可再次切回。" : "切换后使用目标目录已有的模组、存档、游戏设置和备份。原目录中的文件会保留，可再次切回。")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Text("文件统计包含该目录对应的内容来源记录和世界备份。此次操作只切换使用位置，不复制文件。").font(.caption).foregroundStyle(.secondary)
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
                Button("刷新预览", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(loading || model.busy)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("使用目标现有内容") { if let preview { model.changeGameRunDirectory(preview) } }
                    .buttonStyle(.borderedProminent).disabled(preview == nil || loading || model.busy)
            }
            if model.busy { ProgressView("正在切换目录…").controlSize(.small) }
        }.padding(24).frame(width: 620, height: 540)
        .interactiveDismissDisabled(model.busy)
        .task(id: target.rawValue + refresh.uuidString) {
            preview = nil; issue = nil; loading = true
            do {
                let result = try await GameRunDirectoryChange(paths: model.paths).preview(instanceID: instance.id, target: target)
                try Task.checkCancellation(); preview = result
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { loading = false }
        }
        .onChange(of: model.state.instances.first(where: { $0.id == instance.id })?.runDirectory) {
            if model.state.instances.first(where: { $0.id == instance.id })?.runDirectory == target { dismiss() }
        }
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
