import SwiftUI
import AppKit
import RuriCore

struct RepositoryImportRecoveryView: View {
    @Environment(AppModel.self) private var model
    let directoryID: UUID
    @State private var pending: [RepositoryImportRecovery] = []
    @State private var issue: String?
    private var refreshKey: String { "\(directoryID):\(model.busy):\(model.state.revision?.uuidString ?? "")" }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pending) { item in
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(item.registered ? "导入收尾" : "未完成的整合包导入")：\(item.name)", systemImage: "shippingbox.and.arrow.backward").font(.headline)
                        Text(item.canFinish ? "安装文件已准备好，可以完成导入。" : "导入尚未完成。可以保留工作文件并取消，再重新导入整合包。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            if item.canFinish { Button("完成导入") { recover(item, finish: true) }.buttonStyle(.borderedProminent).disabled(model.busy) }
                            if !item.registered { Button("保留文件并取消导入") { recover(item, finish: false) }.disabled(model.busy) }
                            Button("查看工作文件") { NSWorkspace.shared.open(item.workspace) }
                        }
                    }
                }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
        .task(id: refreshKey) {
            guard !model.busy else { return }
            let paths = model.basePaths
            do {
                let result = try await Task.detached(priority: .utility) { try RepositoryImportStore.pending(directoryID: directoryID, paths: paths) }.value
                try Task.checkCancellation(); pending = result; issue = nil
            } catch { if !Task.isCancelled { issue = error.localizedDescription } }
        }
    }
    private func recover(_ item: RepositoryImportRecovery, finish: Bool) {
        let base = model.basePaths
        model.perform(finish ? "完成整合包导入" : "保留导入工作文件") { _ in
            let kept = try await Task.detached(priority: .userInitiated) {
                try RepositoryImportStore.recover(item.id, directoryID: directoryID, finish: finish, paths: base)
            }.value
            model.acceptState(try StateStore.load(base))
            model.notice = finish ? "\(item.name) 已导入" : "已取消导入，工作文件已保留。"
            model.noticeFileURL = kept
            pending.removeAll { $0.id == item.id }
        }
    }
}
