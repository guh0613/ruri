import RuriLocalization
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore

struct GameDiagnosticView: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    let collecting: Bool
    let action: (GameDiagnosis.Action) -> Void
    @State private var diagnosis: GameDiagnosis?
    @State private var error: String?
    @State private var bundle: GameDiagnosticBundle?
    @State private var selected: Set<String> = []
    @State private var previewID: String?
    @State private var privateText = ""
    @State private var appliedPrivateText = ""
    @State private var page = 0
    @State private var generation = UUID()
    @State private var preparing = false
    @State private var exporting = false
    @State private var collectionRequest = UUID()
    @State private var exported: URL?
    private var previewFile: GameDiagnosticBundle.File? { bundle?.files.first { $0.id == previewID } }
    private var previewPages: Int { max(1, ((previewFile?.text.count ?? 0) + 11999) / 12000) }
    private var key: String { "\(session.id)-\(session.updatedAt.timeIntervalSince1970)-\(session.evidence.count)-\(collecting)-\(collectionRequest)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let host = session.host { Text(host.summary).font(.callout).foregroundStyle(.secondary) }
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let diagnosis {
                if collecting { collection(diagnosis) } else { analysis(diagnosis) }
            } else { ProgressView(Messages.AppGameDiagnosticView.readingEvidence.localized).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: key) {
            if collecting && bundle != nil { return }
            generation = UUID()
            diagnosis = nil; bundle = nil; error = nil; exported = nil
            let paths = model.paths, record = session, includeGameLogs = collecting
            let work = Task.detached(priority: .utility) { try GameDiagnosticAnalyzer.load(paths: paths, session: record, includeGameLogs: includeGameLogs) }
            do {
                let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation(); diagnosis = value
                if collecting { await prepareBundle(value) }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .onChange(of: previewID) { page = 0 }
    }
    private func analysis(_ diagnosis: GameDiagnosis) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(diagnosis.title).font(.title3.bold())
                    Text(diagnosis.summary).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(Messages.AppGameDiagnosticView.recordedFacts.localized) {
                    ForEach(diagnosis.facts, id: \.self) { Text($0).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
                ForEach(diagnosis.findings) { finding in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(finding.title).font(.headline)
                            Spacer(minLength: 6)
                            Text(finding.confidence.title).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(finding.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
                        ForEach(finding.evidence) { evidence in
                            let document = diagnosis.documents.first { $0.id == evidence.documentID }
                            DisclosureGroup(Messages.AppGameDiagnosticView.evidenceLine(String(describing: document?.title ?? evidence.documentID), String(describing: document?.isTail == true ? Messages.AppGameDiagnosticView.lastSection.localized : ""), String(describing: evidence.line)).localized) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(evidence.excerpt).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let relative = document?.relativePath { Button(Messages.AppGameDiagnosticView.showEvidenceInFinder.localized) { reveal(relative) } }
                                }.padding(10).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }.font(.caption)
                        }
                        ForEach(Array(finding.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top) {
                                Text("\(index + 1).").foregroundStyle(.secondary)
                                Text(step).fixedSize(horizontal: false, vertical: true)
                            }.font(.callout)
                        }
                        HStack {
                            ForEach(finding.actions, id: \.self) { item in
                                Button(item.title) { action(item) }
                                    .disabled(item == .repair && (model.busy || model.isInstanceInUse(session.instanceID)))
                            }
                        }.controlSize(.small)
                        if finding.actions.contains(.repair) {
                            Text(Messages.AppGameDiagnosticView.repairNotice.localized).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
                if model.busy, let activity = model.activeActivity {
                    HStack { ProgressView().controlSize(.small); Text(activity.progress.stage).font(.callout) }
                }
                if !diagnosis.limitations.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Messages.AppGameDiagnosticView.evidenceScope.localized).font(.headline)
                        ForEach(diagnosis.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Button(Messages.AppGameDiagnosticView.viewRunFiles.localized) { action(.files) }
                    Spacer()
                    Button(Messages.AppGameDiagnosticView.collectReport.localized) { action(.collect) }
                }
            }.padding(.vertical, 4).padding(.trailing, 5)
        }
    }
    private func collection(_ diagnosis: GameDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Messages.AppGameDiagnosticView.collectionInstructions.localized).font(.headline)
                Spacer()
                Button(Messages.NativeGameLogs.collectAgain.localized) { bundle = nil; collectionRequest = UUID() }.disabled(preparing || exporting)
            }
            Text(Messages.NativeGameLogs.collectionHelp.localized).font(.caption).foregroundStyle(.secondary)
            Text(Messages.AppGameDiagnosticView.redactionNotice.localized).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let bundle {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(bundle.files) { file in
                                HStack(alignment: .top, spacing: 7) {
                                    Toggle(Messages.AppGameDiagnosticView.containsFile(file.title).localized, isOn: Binding(get: { selected.contains(file.id) }, set: { if $0 { selected.insert(file.id) } else { selected.remove(file.id) } }))
                                        .toggleStyle(.checkbox).labelsHidden()
                                    Button { previewID = file.id } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.title).font(.callout).multilineTextAlignment(.leading)
                                            Text("\(LocalizedFormat.bytes(Int64(file.byteCount)))\(file.changedByRedaction ? Messages.AppGameDiagnosticView.redacted.localized : "")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).foregroundStyle(previewID == file.id ? Color.accentColor : .primary)
                                }
                            }
                        }.padding(9)
                    }.frame(width: 214)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(previewFile?.path ?? Messages.AppGameDiagnosticView.choosePreview.localized).font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { page -= 1 } label: { Image(systemName: "chevron.left") }.disabled(page == 0).help(Messages.AppGameDiagnosticView.previousPage.localized)
                            Text("\(page + 1) / \(previewPages)").font(.caption).monospacedDigit()
                            Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled(page + 1 >= previewPages).help(Messages.AppGameDiagnosticView.nextPage.localized)
                        }.controlSize(.small)
                        ScrollView {
                            Text(String((previewFile?.text ?? "").dropFirst(page * 12000).prefix(12000)))
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(maxHeight: .infinity)
                HStack(alignment: .top) {
                    TextField(Messages.AppGameDiagnosticView.extraHiddenText.localized, text: $privateText, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                        .onChange(of: privateText) { if privateText.count > 8192 { privateText = String(privateText.prefix(8192)) } }
                    Button(Messages.AppGameDiagnosticView.updatePreview.localized) { Task { await prepareBundle(diagnosis, preserveSelection: true) } }.disabled(preparing || exporting)
                }
                if privateText != appliedPrivateText { Text(Messages.AppGameDiagnosticView.previewChanged.localized).font(.caption).foregroundStyle(.orange) }
                HStack {
                    if preparing || exporting { ProgressView().controlSize(.small) }
                    else if let exported { Button(Messages.AppGameDiagnosticView.showExportedBundle.localized) { NSWorkspace.shared.activateFileViewerSelecting([exported]) } }
                    else { Text(Messages.AppGameDiagnosticView.exportNotice.localized).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button(Messages.AppGameDiagnosticView.exportBundle.localized) { export(bundle) }.buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty || preparing || exporting || privateText != appliedPrivateText)
                }
            } else { ProgressView(Messages.AppGameDiagnosticView.prepareSharePreview.localized).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
    private func prepareBundle(_ diagnosis: GameDiagnosis, preserveSelection: Bool = false) async {
        preparing = true; defer { preparing = false }
        let record = session, text = privateText, request = generation
        let values = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let work = Task.detached { try GameDiagnosticBundle.preview(session: record, diagnosis: diagnosis, additionalPrivateText: values) }
        do {
            let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            guard record.id == session.id && request == generation else { return }
            bundle = value; appliedPrivateText = text; exported = nil; error = nil
            if !preserveSelection { selected = Set(value.files.map(\.id)); previewID = value.files.first?.id }
            page = 0
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
    private func reveal(_ relative: String) {
        do {
            let directory = try GameSessionStore.directory(paths: model.paths, instanceID: session.instanceID, sessionID: session.id)
            NSWorkspace.shared.activateFileViewerSelecting([try LauncherPaths.safePath(relative, within: directory)])
        } catch { self.error = error.localizedDescription }
    }
    private func export(_ snapshot: GameDiagnosticBundle) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "ruri-diagnostic-\(session.id.uuidString.prefix(8)).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let ids = selected, paths = model.paths
        exporting = true; error = nil
        Task {
            defer { exporting = false }
            do {
                try await Task.detached { try snapshot.export(selectedIDs: ids, to: url, paths: paths) }.value
                exported = url
            } catch { self.error = error.localizedDescription }
        }
    }
}
