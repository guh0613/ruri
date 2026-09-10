import SwiftUI
import RuriCore

enum ContentStatusFilter: String, CaseIterable, Identifiable {
    case all, enabled, disabled
    var id: String { rawValue }
    var title: String { switch self { case .all: "全部状态"; case .enabled: "已启用"; case .disabled: "已停用" } }
}
struct ContentRemovalSelection: Identifiable {
    let id = UUID()
    let files: [LocalContentFile]
}
struct ContentRemovalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let files: [LocalContentFile]
    let instanceID: UUID
    let remove: @MainActor @Sendable () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("移除 \(files.count) 项游戏内容").font(.title2.bold())
            Text("所选文件会一起移到废纸篓。若仍有已启用的内容依赖它们，整批操作会停止。").font(.callout).foregroundStyle(.secondary)
            List(files) { file in
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.title).font(.headline)
                    Text(file.url.lastPathComponent).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }.listStyle(.bordered)
            HStack {
                Text(ByteCountFormatter.string(fromByteCount: files.reduce(0) { $0 + $1.size }, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("移到废纸篓", role: .destructive) { remove(); dismiss() }.disabled(model.busy || model.isInstanceInUse(instanceID))
            }
        }.padding(24).frame(width: 500, height: 430)
    }
}
