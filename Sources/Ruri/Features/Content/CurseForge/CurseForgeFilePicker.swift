import SwiftUI
import AppKit
import RuriCore

struct CurseForgeFileRow: View {
    @Environment(AppModel.self) private var model
    let file: CurseForgeFile
    let title: String
    let page: URL
    let manual: Bool
    @Binding var selectedURL: URL?
    @State private var checking = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(file.fileName).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(ByteCountFormatter.string(fromByteCount: file.fileLength, countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if manual {
                    if checking { ProgressView().controlSize(.small) }
                    else if selectedURL != nil { Label("已校验", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent) }
                    else { TagPill(text: "手动下载") }
                } else { Label("自动下载", systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
            }
            if manual {
                HStack { Link("打开下载页面", destination: page); Spacer(); Button(selectedURL == nil ? "选择已下载文件…" : "重新选择…") { choose() }.disabled(checking) }.font(.callout)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .task(id: file.id) {
            if manual, selectedURL == nil, let cached = await CurseForgeService.cachedFile(file, paths: model.paths), !Task.isCancelled { selectedURL = cached }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = "选择 \(file.fileName)。Ruri 会核对版本、大小与校验值。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        checking = true; error = nil
        Task {
            do {
                let cached = try await CurseForgeService.cacheManualFile(url, file: file, paths: model.paths)
                selectedURL = cached
            } catch { self.error = error.localizedDescription }
            checking = false
        }
    }
}

struct CurseForgePlanFiles: View {
    let files: [PlannedCurseFile]
    @Binding var manualFiles: [Int: URL]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if files.contains(where: \.requiresManualDownload) {
                Text("部分作者要求从 CurseForge 页面下载。下载对应版本后选择文件，校验通过即可继续安装。").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(files) { item in
                CurseForgeFileRow(file: item.file, title: item.project.name, page: item.pageURL, manual: item.requiresManualDownload,
                                  selectedURL: Binding(get: { manualFiles[item.id] }, set: { manualFiles[item.id] = $0 }))
            }
        }
    }
}
