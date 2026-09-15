import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore
import RuriLocalization

/// The normal path is collect → save. File selection and extra redaction are
/// available for people who need them, without turning export into a wizard.
struct GameReportExportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: GameSession
    @State private var original: GameDiagnosticBundle?
    @State private var bundle: GameDiagnosticBundle?
    @State private var selected: Set<String> = []
    @State private var previewID: String?
    @State private var review = false
    @State private var privacy = false
    @State private var privateText = ""
    @State private var appliedText = ""
    @State private var working = false
    @State private var collecting = true
    @State private var request = UUID()
    @State private var error: String?
    @State private var exported: URL?
    private var preview: GameDiagnosticBundle.File? { bundle?.files.first { $0.id == previewID } }
    private var selectedBytes: Int { bundle?.files.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.byteCount } ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(Messages.SessionUI.reportTitle.localized).font(.title2.bold())
                Spacer()
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: exported == nil ? "doc.zipper" : "checkmark.circle.fill").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(collecting ? Messages.SessionUI.reportPreparing.localized : bundle == nil ? Messages.SessionUI.reportTitle.localized : exported == nil ? Messages.SessionUI.reportReady.localized : Messages.SessionUI.reportSaved.localized).font(.headline)
                            Text(session.instanceName).font(.callout)
                            if bundle != nil {
                                Text(Messages.SessionUI.reportContents(Int64(selected.count), LocalizedFormat.bytes(Int64(selectedBytes))).localized).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(Messages.SessionUI.reportPrivacy.localized).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let bundle {
                        DisclosureGroup(Messages.SessionUI.reviewFiles.localized, isExpanded: $review) {
                            HSplitView {
                                List(selection: $previewID) {
                                    ForEach(bundle.files) { file in
                                        HStack(alignment: .top, spacing: 8) {
                                            Toggle(file.title, isOn: Binding(get: { selected.contains(file.id) }, set: { included in
                                                if included { selected.insert(file.id) } else { selected.remove(file.id) }
                                            })).toggleStyle(.checkbox).labelsHidden()
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(file.title).font(.callout).lineLimit(2)
                                                Text(LocalizedFormat.bytes(Int64(file.byteCount))).font(.caption).foregroundStyle(.secondary)
                                            }
                                        }.padding(.vertical, 3).tag(file.id)
                                    }
                                }.frame(minWidth: 200, idealWidth: 220, maxWidth: 270)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(preview?.path ?? "—").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    if preview?.previewTruncated == true { Text(Messages.SessionUI.fullFilePreview.localized).font(.caption).foregroundStyle(.secondary) }
                                    GameLogTextView(text: preview?.text ?? "").id(previewID)
                                }.padding(.leading, 10).frame(minWidth: 280)
                            }.frame(height: 270).padding(.top, 10)
                        }.font(.callout)
                        DisclosureGroup(Messages.SessionUI.extraRedaction.localized, isExpanded: $privacy) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField(Messages.SessionUI.extraRedaction.localized, text: $privateText, axis: .vertical)
                                    .lineLimit(2...3).textFieldStyle(.roundedBorder)
                                    .onChange(of: privateText) { if privateText.count > 8192 { privateText = String(privateText.prefix(8192)) } }
                                HStack {
                                    if privateText != appliedText { Text(Messages.AppGameDiagnosticView.previewChanged.localized).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    Button(Messages.AppGameDiagnosticView.updatePreview.localized) { updateRedaction() }.disabled(working)
                                }
                            }.padding(.top, 10)
                        }.font(.callout)
                    }
                    if let error {
                        HStack {
                            Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                            Spacer()
                            if !collecting { Button(Messages.SessionUI.retry.localized) { request = UUID() } }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollBounceBehavior(.basedOnSize).disabled(working)
            HStack {
                if working || collecting { ProgressView().controlSize(.small) }
                if let exported { Button(Messages.SessionUI.showFile.localized) { NSWorkspace.shared.activateFileViewerSelecting([exported]) } }
                Spacer()
                Button(Messages.SessionUI.exportZIP.localized) { export() }.buttonStyle(.borderedProminent)
                    .disabled(bundle == nil || selected.isEmpty || working || collecting || privateText != appliedText)
            }
        }.padding(24).frame(width: 750, height: review ? 660 : privacy ? 460 : 360)
        .task(id: request) {
            let generation = request, privateInput = privateText
            collecting = true; error = nil
            defer { if generation == request { collecting = false } }
            let paths = model.paths, record = session
            let work = Task.detached(priority: .utility) {
                let base = try GameDiagnosticBundle.collect(paths: paths, session: record)
                return try (base, base.redacting(privateInput.components(separatedBy: .newlines).filter { !$0.isEmpty }))
            }
            do {
                let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                original = result.0; bundle = result.1; appliedText = privateInput
                selected = Set(result.1.files.map(\.id)); previewID = result.1.files.first?.id
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    private func updateRedaction() {
        guard let original else { return }
        working = true
        let input = privateText
        Task {
            defer { working = false }
            do {
                let result = try await Task.detached(priority: .utility) { try original.redacting(input.components(separatedBy: .newlines).filter { !$0.isEmpty }) }.value
                bundle = result; appliedText = input; exported = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    private func export() {
        guard let bundle else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "ruri-diagnostic-\(session.id.uuidString.prefix(8)).zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let paths = model.paths, selected = selected
        working = true; error = nil
        Task {
            defer { working = false }
            do {
                try await Task.detached(priority: .utility) { try bundle.export(selectedIDs: selected, to: destination, paths: paths) }.value
                exported = destination
            } catch { self.error = error.localizedDescription }
        }
    }
}
