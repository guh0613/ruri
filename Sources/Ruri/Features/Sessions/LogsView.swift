import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private enum Mode: String, CaseIterable {
        case analysis, logs, share
        var title: String { switch self { case .analysis: Messages.AppLogsView.diagnosticsAndHandling.localized; case .logs: Messages.AppLogsView.runLogs.localized; case .share: Messages.AppLogsView.collectReport.localized } }
    }
    private enum Destination: String, Identifiable { case settings, mods; var id: String { rawValue } }
    @State private var mode = Mode.logs
    @State private var destination: Destination?
    @State private var filter = ""
    @State private var follow = true
    @State private var selectedID: UUID?
    @State private var historicalLines: [String] = []
    @State private var readError: String?
    private var session: GameSession? { model.sessions.first { $0.id == selectedID } }
    private var isCurrent: Bool { selectedID.map { model.liveLogs[$0] != nil } ?? false }
    private var isRunning: Bool { session.map { model.activeSessions[$0.instanceID]?.id == $0.id } ?? false }
    private var lines: [String] {
        (selectedID.flatMap { model.liveLogs[$0] } ?? historicalLines).filter { filter.isEmpty || $0.localizedCaseInsensitiveContains(filter) }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(Messages.AppLogsView.runHistory.localized).font(.title2.bold()); Spacer()
                if isRunning, let session { TagPill(text: model.runningLabel(session.instanceID) ?? Messages.AppLogsView.running.localized) }
                Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if model.sessions.isEmpty {
                ContentUnavailableView(Messages.AppLogsView.noRunHistory.localized, systemImage: "text.document", description: Text(Messages.AppLogsView.runHistoryDetails.localized))
            } else {
                Picker(Messages.AppLogsView.selectRecord.localized, selection: $selectedID) {
                    ForEach(model.sessions) { record in
                        Text("\(LocalizedFormat.date(record.createdAt, date: .abbreviated, time: .standard)) · \(record.instanceName)").tag(Optional(record.id))
                    }
                }
                Picker(Messages.AppLogsView.viewContent.localized, selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if let session, !session.state.isFinished, session.monitorIdentity != nil || !model.busy {
                    GameSessionRecoveryView(session: session).id(session.id)
                }
                if mode != .logs, let session {
                    GameDiagnosticView(session: session, collecting: mode == .share, action: diagnosticAction).id(session.id)
                } else {
                    if let session { summary(session) }
                    HStack {
                        TextField(Messages.AppLogsView.filterLogs.localized, text: $filter).textFieldStyle(.roundedBorder)
                        Toggle(Messages.AppLogsView.autoScroll.localized, isOn: $follow).toggleStyle(.checkbox)
                        Button(Messages.AppLogsView.exportFullLog.localized) { export() }.disabled(session == nil)
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
                            .onChange(of: lines.last) { if follow && isCurrent { proxy.scrollTo("end", anchor: .bottom) } }
                    }
                    if isRunning, let session, !session.state.isFinished, session.monitorIdentity?.isAlive == true {
                        GameQuitControls(session: session)
                    }
                    HStack {
                        Text(Messages.AppLogsView.recentLogPreview.localized).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }.padding(22).frame(width: 780, height: 660)
            .sheet(item: $destination) { target in
                if let record = session, let instance = model.state.instances.first(where: { $0.id == record.instanceID }) {
                    switch target {
                    case .settings: InstanceSettingsView(instance: instance)
                    case .mods: InstanceContentView(instance: instance)
                    }
                }
            }
            .task {
                await model.refreshSessions()
                selectedID = model.requestedLogSessionID ?? model.logsSessionID ?? model.sessions.first?.id
                loadHistory()
            }
            .onChange(of: selectedID) { loadHistory(); mode = session?.state == .failed ? .analysis : .logs }
            .onChange(of: session?.state) {
                if let session {
                    model.acknowledgeSession(session)
                    if session.state == .failed && mode != .share { mode = .analysis }
                }
            }
            .onChange(of: isCurrent) { loadHistory() }
            .onChange(of: model.requestedLogSessionID) { if let id = model.requestedLogSessionID { selectedID = id } }
    }
    @ViewBuilder private func summary(_ record: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(isRunning ? Messages.AppLogsView.lastRecordedStage(record.stage.title).localized : record.title).font(.headline)
            if let exit = record.exit {
                Text(exit.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let interruption = record.interruption {
                Text(interruption.displayExplanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else if let failure = record.displayFailure {
                Text(failure).font(.callout).foregroundStyle(.orange).lineLimit(3).textSelection(.enabled)
            }
            ForEach(Array((record.commandResults ?? []).enumerated()), id: \.offset) { _, result in
                Text(result.summary).font(.caption).foregroundStyle(result.succeeded ? Color.secondary : .orange).textSelection(.enabled)
            }
            DisclosureGroup(Messages.AppLogsView.stageEnvironmentAndReport.localized) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Minecraft \(record.gameVersion) · \(record.loader) \(record.loaderVersion ?? "")").font(.caption)
                        Text(record.memory?.summary ?? Messages.AppLogsView.recordedMemoryLimit(String(describing: record.memoryMB)).localized).font(.caption).textSelection(.enabled)
                        Text("\(record.operatingSystem) · \(record.java ?? Messages.AppLogsView.javaNotSelected.localized)").font(.caption).foregroundStyle(.secondary)
                        ForEach(record.events) { event in
                            HStack(alignment: .top) {
                                Text(LocalizedFormat.date(event.date, date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                                Text(event.displayMessage).textSelection(.enabled)
                            }.font(.caption)
                        }
                        ForEach(record.evidence) { evidence in
                            Button(evidence.name + (evidence.truncated ? Messages.AppLogsView.truncatedCopy.localized : "")) { reveal(record, relativePath: evidence.relativePath) }
                        }
                        Button(Messages.AppLogsView.showRunRecordInFinder.localized) { reveal(record) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }.frame(maxHeight: 125)
            }.font(.caption)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func diagnosticAction(_ action: GameDiagnosis.Action) {
        guard let record = session else { return }
        switch action {
        case .collect: mode = .share
        case .files: reveal(record)
        case .accounts: model.page = .accounts; dismiss()
        case .settings: destination = .settings
        case .mods: destination = .mods
        case .repair:
            if let instance = model.state.instances.first(where: { $0.id == record.instanceID }) { model.repair(instance) }
        }
    }
    private func loadHistory() {
        readError = nil; historicalLines = []
        guard let session else { return }
        model.acknowledgeSession(session)
        guard !isCurrent else { return }
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
