import SwiftUI
import AppKit
import UniformTypeIdentifiers
import RuriCore
import RuriLocalization

struct GameConsoleView: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    private enum Source: Hashable, Sendable {
        case console, launcher, debug, process
        case report(String)
        var stored: GameSessionStore.LogSource? { switch self { case .console: .console; case .launcher: .launcher; case .debug: .nativeDebug; case .process: .fallback; case .report: nil } }
        var isReport: Bool { if case .report = self { true } else { false } }
    }
    @State private var source = Source.console
    @State private var text = ""
    @State private var displayText = ""
    @State private var revision = 0
    @State private var search = ""
    @State private var follow = true
    @State private var selecting = false
    @State private var pendingText: String?
    @State private var visible = false
    @State private var loading = false
    @State private var error: String?
    @State private var retry = UUID()
    @State private var origin: String?
    @State private var processOutput = false
    @State private var liveFallback = false
    @State private var reports: [GameDiagnosticDocument] = []
    @State private var reportRevision = 0
    @State private var reportError: String?
    private var selectedReport: GameDiagnosticDocument? {
        guard case .report(let id) = source else { return nil }
        return reports.first { $0.id == id }
    }
    private var reportKey: String { "\(session.id)|\(visible)|\(session.state)|\(session.exit != nil)|\(session.evidence.count)|\(session.artifactState?.rawValue ?? "")|\(retry)" }
    private var key: String {
        "\(session.id)|\(source)|\(visible)|\(session.controlEndpoint ?? "")|\(session.state.isFinished)|\(session.exit != nil)|\(source == .launcher || session.state.isFinished ? session.updatedAt.timeIntervalSince1970 : 0)|\(retry)|\(reportRevision)"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker(Messages.SessionUI.logSource.localized, selection: $source) {
                    Text(Messages.SessionUI.nativeGameLog.localized).tag(Source.console)
                    Text(Messages.SessionUI.launcherLog.localized).tag(Source.launcher)
                    Text(Messages.SessionUI.nativeDebugLog.localized).tag(Source.debug)
                    Text(Messages.SessionUI.processOutput.localized).tag(Source.process)
                    if !reports.isEmpty {
                        Divider()
                        ForEach(reports) { report in
                            Text(reportTitle(report)).tag(Source.report(report.id))
                        }
                    }
                }.labelsHidden().frame(width: source.isReport ? 240 : 155)
                TextField(Messages.SessionUI.logSearch.localized, text: $search).textFieldStyle(.roundedBorder)
                if !source.isReport { Toggle(Messages.SessionUI.follow.localized, isOn: $follow).toggleStyle(.checkbox) }
            }.padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            GameLogTextView(text: displayText, follow: follow && !source.isReport, onSelection: { selecting = $0 }).id(source)
                .overlay {
                    if text.isEmpty {
                        if loading { ProgressView() }
                        else { Text(source.isReport ? Messages.SessionUI.reportNotAvailable.localized : session.state.isFinished && source != .launcher ? Messages.SessionUI.nativeLogUnavailable.localized : Messages.SessionUI.emptyLog.localized).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(32) }
                    }
                }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if let error {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(Messages.SessionUI.retry.localized) { retry = UUID() }
                    }
                }
                if let origin { Text(Messages.SessionUI.logOrigin(origin).localized).font(.caption).foregroundStyle(.secondary) }
                if selectedReport?.truncated == true { Text(Messages.SessionUI.reportExcerpt.localized).font(.caption).foregroundStyle(.secondary) }
                if let reportError {
                    HStack {
                        Text(reportError).font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button(Messages.SessionUI.retry.localized) { retry = UUID() }
                    }
                }
                if processOutput { Text(Messages.SessionUI.fallbackLogHelp.localized).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button(source.isReport ? Messages.SessionUI.showFile.localized : Messages.SessionUI.openGameFolder.localized) { revealLogs() }
                        .disabled(source.isReport ? reportURL == nil : !model.state.instances.contains { $0.id == session.instanceID })
                    Spacer()
                    Button(source.isReport ? Messages.SessionUI.saveVisibleReport.localized : Messages.SessionUI.saveVisibleLog.localized) { export() }.disabled(displayText.isEmpty)
                }.controlSize(.small)
                if !source.isReport {
                    Text(session.debugLogging == true ? Messages.MonitorLogging.debugModeHelp.localized : Messages.SessionRuntime.loggingHelp.localized)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(.horizontal, 24).padding(.vertical, 14)
        }
        .background(WindowVisibilityReader { visible = $0 })
        .task(id: reportKey) {
            guard visible, session.hasPlayed, session.exit != nil || session.state.isFinished else { return }
            let paths = model.paths, record = session
            reportError = nil
            let work = Task.detached(priority: .utility) { try GameEvidenceCollector.reports(paths: paths, session: record) }
            do {
                let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                let previous = selectedReport
                reports = value
                reportRevision += 1
                if source.isReport, selectedReport == nil {
                    source = reports.first(where: { $0.title == previous?.title && $0.kind == previous?.kind }).map { .report($0.id) } ?? .console
                }
            } catch { if !Task.isCancelled { reportError = error.localizedDescription } }
        }
        .task(id: key) {
            liveFallback = false
            guard visible else { return }
            loading = true; error = nil
            defer { loading = false }
            if source.isReport {
                origin = selectedReport?.title; processOutput = false
                replace(selectedReport?.text ?? "")
                return
            }
            guard let logSource = source.stored else { return }
            let record = session, paths = model.paths
            do {
                let cursor = try GameSessionLogCursor(paths: paths, session: record, source: logSource)
                while !Task.isCancelled {
                    let game = record.gameDirectory ?? paths.game(record.instanceID)
                    let directory = try GameSessionStore.directory(paths: paths, instanceID: record.instanceID, sessionID: record.id)
                    let watched = logSource == .launcher
                        ? GameHistoryStore.observationURLs(paths: paths)
                        : [game, game.appendingPathComponent("logs"), game.appendingPathComponent("logs/latest.log"), game.appendingPathComponent("logs/debug.log"), directory, directory.appendingPathComponent("console.log"), directory.appendingPathComponent("console-tail.log")]
                    let observer = FileChangeObserver(directories: watched, fallbackSeconds: 3)
                    defer { observer.cancel() }
                    _ = try await cursor.refresh(final: record.state.isFinished)
                    try Task.checkCancellation()
                    let value = await cursor.preview
                    origin = value.origin; processOutput = value.isProcessOutput
                    liveFallback = value.needsLiveOutput
                    if !liveFallback { replace(value.text) }
                    loading = false
                    if record.state.isFinished { return }
                    var events = observer.events.makeAsyncIterator()
                    _ = await events.next()
                    observer.cancel()
                    // Event-driven, coalesced reads. No output observer survives
                    // a hidden/closed window, and a burst cannot redraw per line.
                    try await Task.sleep(for: .seconds(1))
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .task(id: "\(key)|\(liveFallback)") {
            guard visible, liveFallback else { return }
            let record = session
            if record.controlEndpoint != nil {
                let observation = GameMonitorObservation(session: record, includeOutput: true)
                defer { observation.cancel() }
                do {
                    for try await update in observation.updates {
                        try Task.checkCancellation()
                        guard liveFallback else { return }
                        if let output = update.output {
                            replace(output.text); origin = Messages.SessionUI.processOutput.localized; processOutput = true
                        }
                        if let record = update.session { model.publishSession(record) }
                    }
                } catch { if !Task.isCancelled { self.error = Messages.SessionUI.noLiveConnection.localized } }
            } else { error = Messages.SessionUI.noLiveConnection.localized }
        }
        .task(id: "\(revision)|\(search)") {
            let input = text, query = search, report = source.isReport
            let value = await Task.detached(priority: .utility) {
                let all = input.split(separator: "\n", omittingEmptySubsequences: false)
                let lines = report ? all[...] : all.suffix(5000)
                return lines.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }.joined(separator: "\n")
            }.value
            if !Task.isCancelled { displayText = value }
        }
        .onChange(of: source) { selecting = false; pendingText = nil; origin = nil; processOutput = false; liveFallback = false; replace("") }
        .onChange(of: selecting) {
            if !selecting, let pending = pendingText { pendingText = nil; replace(pending) }
        }
    }
    private func replace(_ value: String) {
        if selecting { pendingText = value; return }
        guard text != value else { return }
        text = value; revision &+= 1
    }
    private func reportTitle(_ report: GameDiagnosticDocument) -> String {
        let title = switch report.kind {
        case .systemReport: Messages.SessionUI.macosCrashReport.localized
        case .jvmReport: Messages.SessionUI.jvmCrashReport.localized
        default: Messages.SessionUI.minecraftCrashReport.localized
        }
        return reports.filter { $0.kind == report.kind }.count > 1 ? title + " · " + report.title : title
    }
    private var reportURL: URL? {
        guard let report = selectedReport else { return nil }
        if let relative = report.relativePath,
           let directory = try? GameSessionStore.directory(paths: model.paths, instanceID: session.instanceID, sessionID: session.id) {
            return try? LauncherPaths.safePath(relative, within: directory)
        }
        if let relative = report.gameRelativePath {
            return try? LauncherPaths.safePath(relative, within: session.gameDirectory ?? model.paths.game(session.instanceID))
        }
        if report.kind == .systemReport {
            return try? LauncherPaths.safePath(report.title, within: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports"))
        }
        return nil
    }
    private func revealLogs() {
        if source.isReport {
            if let reportURL { NSWorkspace.shared.activateFileViewerSelecting([reportURL]) }
            return
        }
        let game = model.paths.game(session.instanceID), logs = model.paths.game(session.instanceID).appendingPathComponent("logs")
        NSWorkspace.shared.activateFileViewerSelecting([FileManager.default.fileExists(atPath: logs.path) ? logs : game])
    }
    private func export() {
        let value = displayText, paths = model.paths, session = session
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = selectedReport.map { $0.title + ".txt" } ?? "ruri-\(session.id.uuidString.prefix(8)).log"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do { try await Task.detached(priority: .utility) { try GameSessionStore.exportPreview(value, paths: paths, session: session, to: destination) }.value }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// NSTextView provides selection, standard Copy/Find and lazy layout without
/// creating thousands of SwiftUI Text views every time a log batch arrives.
struct GameLogTextView: NSViewRepresentable {
    let text: String
    var follow = false
    var onSelection: ((Bool) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = true; scroll.backgroundColor = .textBackgroundColor
        let view = NSTextView(); view.delegate = context.coordinator
        view.isEditable = false; view.isSelectable = true; view.isRichText = false; view.allowsUndo = false
        view.usesFindPanel = true; view.isContinuousSpellCheckingEnabled = false; view.isGrammarCheckingEnabled = false
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.textColor = .textColor; view.backgroundColor = .textBackgroundColor
        view.textContainerInset = NSSize(width: 16, height: 12)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        view.layoutManager?.allowsNonContiguousLayout = true
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let selection = view.selectedRange(), origin = scroll.contentView.bounds.origin
        guard onSelection == nil || selection.length == 0 else { return }
        view.string = text
        view.setSelectedRange(NSRange(location: min(selection.location, view.string.utf16.count), length: 0))
        if follow && selection.length == 0 { view.scrollToEndOfDocument(nil) }
        else { scroll.contentView.scroll(to: origin); scroll.reflectScrolledClipView(scroll.contentView) }
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.active = false }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GameLogTextView
        var active = true
        init(parent: GameLogTextView) { self.parent = parent }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let selecting = view.selectedRange().length > 0
            DispatchQueue.main.async { [weak self] in
                guard let self, active else { return }
                parent.onSelection?(selecting)
            }
        }
    }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    let change: (Bool) -> Void
    func makeNSView(context: Context) -> VisibilityView { let view = VisibilityView(); view.change = change; return view }
    func updateNSView(_ view: VisibilityView, context: Context) { view.change = change }
    static func dismantleNSView(_ view: VisibilityView, coordinator: ()) { view.stop() }

    final class VisibilityView: NSView {
        var change: ((Bool) -> Void)?
        private var observation: NSObjectProtocol?
        private var lastValue: Bool?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); stop()
            if let window {
                observation = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                }
            }
            report()
        }
        func stop() {
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = nil
        }
        private func report() {
            let value = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
            guard value != lastValue else { return }
            lastValue = value
            DispatchQueue.main.async { [weak self] in self?.change?(value) }
        }
    }
}
