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
    @State private var exported: URL?
    private var previewFile: GameDiagnosticBundle.File? { bundle?.files.first { $0.id == previewID } }
    private var previewPages: Int { max(1, ((previewFile?.text.count ?? 0) + 11999) / 12000) }
    private var key: String { "\(session.id)-\(session.updatedAt.timeIntervalSince1970)-\(session.evidence.count)-\(collecting)" }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if let diagnosis {
                if collecting { collection(diagnosis) } else { analysis(diagnosis) }
            } else { ProgressView("读取本次运行的证据…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: key) {
            if collecting && bundle != nil { return }
            generation = UUID()
            diagnosis = nil; bundle = nil; error = nil; exported = nil
            let paths = model.paths, record = session
            let work = Task.detached { try GameDiagnosticAnalyzer.load(paths: paths, session: record) }
            do {
                let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation(); diagnosis = value
                await prepareBundle(value)
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
                DisclosureGroup("已记录的事实") {
                    ForEach(diagnosis.facts, id: \.self) { Text($0).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
                ForEach(diagnosis.findings) { finding in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(finding.title).font(.headline)
                            Spacer(minLength: 6)
                            Text(finding.confidence.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(finding.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
                        ForEach(finding.evidence) { evidence in
                            let document = diagnosis.documents.first { $0.id == evidence.documentID }
                            DisclosureGroup("\(document?.title ?? evidence.documentID) · 命中\(document?.isTail == true ? "末段" : "")第 \(evidence.line) 行") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(evidence.excerpt).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let relative = document?.relativePath { Button("在 Finder 中显示这份证据") { reveal(relative) } }
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
                            Text("修复会联网校验并补全游戏与加载器安装文件。").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
                if model.busy, let activity = model.activeActivity {
                    HStack { ProgressView().controlSize(.small); Text(activity.progress.stage).font(.callout) }
                }
                if !diagnosis.limitations.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("证据范围").font(.headline)
                        ForEach(diagnosis.limitations, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Button("查看运行文件") { action(.files) }
                    Spacer()
                    Button("收集诊断报告…") { action(.collect) }
                }
            }.padding(.vertical, 4).padding(.trailing, 5)
        }
    }
    private func collection(_ diagnosis: GameDiagnosis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择内容，检查预览，然后保存到本地。").font(.headline)
            Text("已遮盖常见凭据、用户路径、邮箱和连接地址。聊天、坐标及模组自定义字段仍可能包含私人信息；可在下方添加需要隐藏的文字。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let bundle {
                HStack(alignment: .top, spacing: 12) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(bundle.files) { file in
                                HStack(alignment: .top, spacing: 7) {
                                    Toggle("包含 \(file.title)", isOn: Binding(get: { selected.contains(file.id) }, set: { if $0 { selected.insert(file.id) } else { selected.remove(file.id) } }))
                                        .toggleStyle(.checkbox).labelsHidden()
                                    Button { previewID = file.id } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.title).font(.callout).multilineTextAlignment(.leading)
                                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))\(file.changedByRedaction ? " · 已遮盖" : "")")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).foregroundStyle(previewID == file.id ? Color.accentColor : .primary)
                                }
                            }
                        }.padding(9)
                    }.frame(width: 214)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(previewFile?.path ?? "选择一项预览").font(.caption).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { page -= 1 } label: { Image(systemName: "chevron.left") }.disabled(page == 0).help("上一页")
                            Text("\(page + 1) / \(previewPages)").font(.caption).monospacedDigit()
                            Button { page += 1 } label: { Image(systemName: "chevron.right") }.disabled(page + 1 >= previewPages).help("下一页")
                        }.controlSize(.small)
                        ScrollView {
                            Text(String((previewFile?.text ?? "").dropFirst(page * 12000).prefix(12000)))
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(maxHeight: .infinity)
                HStack(alignment: .top) {
                    TextField("额外隐藏的文字，每行一项", text: $privateText, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                        .onChange(of: privateText) { if privateText.count > 8192 { privateText = String(privateText.prefix(8192)) } }
                    Button("更新预览") { Task { await prepareBundle(diagnosis, preserveSelection: true) } }.disabled(preparing || exporting)
                }
                if privateText != appliedPrivateText { Text("隐藏文字已修改，请更新预览后导出。").font(.caption).foregroundStyle(.orange) }
                HStack {
                    if preparing || exporting { ProgressView().controlSize(.small) }
                    else if let exported { Button("显示已导出的诊断包") { NSWorkspace.shared.activateFileViewerSelecting([exported]) } }
                    else { Text("仅保存已勾选的预览内容；没有上传操作。").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Button("导出诊断包…") { export(bundle) }.buttonStyle(.borderedProminent)
                        .disabled(selected.isEmpty || preparing || exporting || privateText != appliedPrivateText)
                }
            } else { ProgressView("准备分享预览…").frame(maxWidth: .infinity, maxHeight: .infinity) }
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
