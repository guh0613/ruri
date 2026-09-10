import SwiftUI
import RuriCore

struct ContentBatchUpdateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let plan: ContentBatchUpdatePlan
    @State private var manualFiles: [Int: URL] = [:]
    private var missingManualFiles: Bool { plan.curseforge.contains { $0.requiresManualDownload && manualFiles[$0.id] == nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "更新 \(plan.selectedIDs.count) 项内容", subtitle: plan.instance.name)
            Text("共 \(plan.records.count) 个文件 · \(ByteCountFormatter.string(fromByteCount: plan.downloadSize, countStyle: .file))").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(plan.records) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.title).font(.headline)
                                Spacer()
                                if !plan.selectedIDs.contains(record.id) { TagPill(text: "必需依赖") }
                            }
                            if let previous = plan.baseline.first(where: { $0.id == record.id }) {
                                Text(previous.versionName + " → " + record.versionName).font(.callout)
                                if !previous.enabled { Text("更新后继续保持停用").font(.caption).foregroundStyle(.secondary) }
                            } else { Text("新增 · " + record.versionName).font(.callout) }
                            Text(record.filename).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Divider()
                    }
                    let manual = plan.curseforge.filter(\.requiresManualDownload)
                    if !manual.isEmpty { CurseForgePlanFiles(files: manual, manualFiles: $manualFiles) }
                }
            }
            Text("下载和校验完成后一起替换文件。停用状态保留，取消或失败时保留原文件。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("更新全部 \(plan.selectedIDs.count) 项") {
                    model.perform("批量更新 \(plan.selectedIDs.count) 项内容", instanceID: plan.instance.id) { id in
                        try await ContentBatchUpdater(curseforge: CurseForgeService(apiKey: "")).install(plan, paths: model.paths, downloader: model.installer.downloader, manualFiles: manualFiles) { p in await model.progress(id, p) }
                        model.notice = "已更新 \(plan.selectedIDs.count) 项内容"
                    }
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(model.busy || model.isInstanceInUse(plan.instance.id) || missingManualFiles)
            }
        }.padding(24).frame(width: 600, height: 570)
    }
}
