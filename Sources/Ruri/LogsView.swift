import SwiftUI
import AppKit
import RuriCore

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var follow = true
    @State private var selectedID: UUID?
    @State private var historicalLines: [String] = []
    @State private var readError: String?
    private var session: GameSession? { model.sessions.first { $0.id == selectedID } }
    private var isCurrent: Bool { selectedID != nil && selectedID == model.logsSessionID }
    private var isRunning: Bool { isCurrent && model.runningID != nil }
    private var lines: [String] {
        (isCurrent ? model.logs : historicalLines).filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("运行记录").font(.title2.bold()); Spacer()
                if isRunning { TagPill(text: "运行中") }
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if model.sessions.isEmpty {
                ContentUnavailableView("暂无运行记录", systemImage: "text.document", description: Text("启动游戏后，这里会保留每次启动的过程和日志。"))
            } else {
                Picker("选择记录", selection: $selectedID) {
                    ForEach(model.sessions) { record in
                        Text("\(record.createdAt.formatted(date: .abbreviated, time: .standard)) · \(record.instanceName)").tag(Optional(record.id))
                    }
                }
                if let session { summary(session) }
                HStack {
                    TextField("筛选日志", text: $filter).textFieldStyle(.roundedBorder)
                    Toggle("自动滚动", isOn: $follow).toggleStyle(.checkbox)
                    Button("导出完整日志…") { export() }.disabled(session == nil)
                }
                if let readError { Text(readError).font(.callout).foregroundStyle(.red) }
                ScrollViewReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line).font(.system(size: 11, design: .monospaced))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .foregroundStyle(line.contains("ERROR") || line.contains("Exception") ? .orange : .primary)
                                    .textSelection(.enabled).id(index)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }.padding(12)
                    }.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: model.logs.count) { if follow && isCurrent { proxy.scrollTo("end", anchor: .bottom) } }
                }
                HStack {
                    Text("预览最近 5,000 行；每次运行的完整日志独立保留。").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if isRunning { Button("结束游戏", role: .destructive) { model.stopGame() } }
                }
            }
        }.padding(22).frame(width: 700, height: 560)
            .onAppear {
                model.refreshSessions()
                selectedID = model.logsSessionID ?? model.sessions.first?.id
                loadHistory()
            }
            .onChange(of: selectedID) { loadHistory() }
    }
    @ViewBuilder private func summary(_ record: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isRunning ? record.stage.title : record.title).font(.headline)
            if let exit = record.exit {
                Text(exit.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let failure = record.failure {
                Text(failure).font(.callout).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
            }
            DisclosureGroup("阶段、环境与报告") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Minecraft \(record.gameVersion) · \(record.loader) \(record.loaderVersion ?? "") · \(record.memoryMB) MB").font(.caption)
                        Text("\(record.operatingSystem) · \(record.java ?? "尚未选择 Java")").font(.caption).foregroundStyle(.secondary)
                        ForEach(record.events) { event in
                            HStack(alignment: .top) {
                                Text(event.date.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                                Text(event.message).textSelection(.enabled)
                            }.font(.caption)
                        }
                        ForEach(record.evidence) { evidence in
                            Button(evidence.name + (evidence.truncated ? "（截断副本）" : "")) { reveal(record, relativePath: evidence.relativePath) }
                        }
                        Button("在 Finder 中显示本次运行记录") { reveal(record) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }.frame(maxHeight: 125)
            }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func loadHistory() {
        readError = nil; historicalLines = []
        guard let session, !isCurrent else { return }
        do {
            historicalLines = Array(try GameSessionStore.logTail(paths: model.paths, session: session).split(separator: "\n", omittingEmptySubsequences: false).suffix(5000).map(String.init))
        } catch { readError = error.localizedDescription }
    }
    private func reveal(_ record: GameSession, relativePath: String? = nil) {
        do {
            let directory = try GameSessionStore.directory(paths: model.paths, instanceID: record.instanceID, sessionID: record.id)
            let url = try relativePath.map { try LauncherPaths.safePath($0, within: directory) } ?? directory
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch { readError = error.localizedDescription }
    }
    private func export() {
        guard let session else { return }
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel(); panel.nameFieldStringValue = "ruri-\(date.string(from: session.createdAt))-\(session.id.uuidString.prefix(8)).log"; panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do { try GameSessionStore.exportLog(paths: model.paths, session: session, to: url) }
            catch { readError = error.localizedDescription }
        }
    }
}
