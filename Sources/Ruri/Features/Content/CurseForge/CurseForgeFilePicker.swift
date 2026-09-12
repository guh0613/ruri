import RuriLocalization
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
                    Text(LocalizedFormat.bytes(file.fileLength)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if manual {
                    if checking { ProgressView().controlSize(.small) }
                    else if selectedURL != nil { Label(Messages.AppCurseForgeFilePicker.verified.localized, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Theme.accent) }
                    else { TagPill(text: Messages.AppCurseForgeFilePicker.manualDownload.localized) }
                } else { Label(Messages.AppCurseForgeFilePicker.automaticDownload.localized, systemImage: "arrow.down.circle").font(.caption).foregroundStyle(.secondary) }
            }
            if manual {
                HStack { Link(Messages.AppCurseForgeFilePicker.openDownloadPage.localized, destination: page); Spacer(); Button(selectedURL == nil ? Messages.AppCurseForgeFilePicker.chooseDownloadedFile.localized : Messages.AppCurseForgeFilePicker.chooseAnotherFile.localized) { choose() }.disabled(checking) }.font(.callout)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
        }.padding(14).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .task(id: file.id) {
            if manual, selectedURL == nil, let cached = await CurseForgeService.cachedFile(file, paths: model.paths), !Task.isCancelled { selectedURL = cached }
        }
    }
    private func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.message = Messages.AppCurseForgeFilePicker.selectFile(file.fileName).localized
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
                Text(Messages.AppCurseForgeFilePicker.manualDownloadNotice.localized).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(files) { item in
                CurseForgeFileRow(file: item.file, title: item.project.name, page: item.pageURL, manual: item.requiresManualDownload,
                                  selectedURL: Binding(get: { manualFiles[item.id] }, set: { manualFiles[item.id] = $0 }))
            }
        }
    }
}
