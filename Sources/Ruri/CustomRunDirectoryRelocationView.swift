import SwiftUI
import AppKit
import RuriCore

struct CustomRunDirectoryRelocationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let instanceID: UUID
    @State private var selected: URL?
    @State private var preview: CustomRunDirectoryRelocationPreview?
    @State private var issue: String?
    @State private var checking = false
    @State private var refresh = UUID()
    private var original: CustomRunDirectory? { model.state.instances.first(where: { $0.id == instanceID })?.customRunDirectory }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(title: "找回原游戏目录", subtitle: "文件夹移动或磁盘位置改变后，更新实例引用。")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("请选择原文件夹现在的位置。使用它的实例会一起更新；当前未使用、但记住此位置的实例也会更新。").font(.callout).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("原位置").font(.headline)
                        Text(original?.url.path ?? "未登记自定义目录").font(.caption).textSelection(.enabled)
                    }
                    HStack {
                        Text(selected?.path ?? "尚未选择新位置").font(.caption).textSelection(.enabled)
                        Spacer()
                        Button("选择原文件夹…", systemImage: "folder") { selectFolder() }.disabled(model.busy || checking)
                    }
                    if checking { ProgressView("正在核对目录身份与运行状态…") }
                    if let preview {
                        Divider()
                        Text("将更新 \(preview.instances.count) 个实例").font(.headline)
                        ForEach(preview.instances) { item in
                            LabeledContent(item.name, value: item.usesDirectory ? "使用此目录" : "记住此位置")
                        }
                        Text("确认后，游戏文件、模组和存档仍保留在所选位置。运行历史留在各自的实例文件夹。").font(.caption).foregroundStyle(.secondary)
                    }
                    if let issue { Label(issue, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(2)
            }
            HStack {
                if selected != nil { Button("重新检查", systemImage: "arrow.clockwise") { refresh = UUID() }.disabled(checking || model.busy) }
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Button("更新目录位置") {
                    if let preview { model.relocateCustomDirectory(preview) { dismiss() } }
                }.buttonStyle(.borderedProminent).disabled(preview == nil || checking || model.busy)
            }
        }.padding(24).frame(width: 630, height: 480)
        .interactiveDismissDisabled(model.busy)
        .task(id: (selected?.path ?? "") + refresh.uuidString) {
            preview = nil; issue = nil
            guard let selected else { return }
            checking = true
            do {
                let value = try await CustomRunDirectoryRelocation(paths: model.paths).preview(instanceID: instanceID, target: selected)
                try Task.checkCancellation(); preview = value
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            if !Task.isCancelled { checking = false }
        }
    }
    private func selectFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.message = "请选择原自定义游戏文件夹现在的位置。只核对身份，不登记新的游戏文件夹。"
        panel.begin { response in if response == .OK, let url = panel.url { selected = url; refresh = UUID() } }
    }
}
