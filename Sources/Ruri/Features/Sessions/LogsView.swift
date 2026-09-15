import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

/// A single run has one clear overview. History browsing and report export are
/// separate screens rather than competing modes in an oversized log picker.
struct LogsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private enum Tab: Hashable { case overview, console }
    private enum Destination: String, Identifiable { case settings, mods; var id: String { rawValue } }
    @State private var tab = Tab.overview
    @State private var loaded: GameSession?
    @State private var error: String?
    @State private var exporting = false
    @State private var destination: Destination?
    private var session: GameSession? {
        let id = model.requestedLogSessionID
        return model.sessions.first(where: { $0.id == id }) ??
            (model.inspectedSession?.id == id ? model.inspectedSession : nil) ??
            (loaded?.id == id ? loaded : nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: session.resultSymbol).font(.system(size: 26)).foregroundStyle(session.resultColor)
                        .frame(width: 36).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.instanceName).font(.title2.bold()).lineLimit(1)
                        HStack(spacing: 8) {
                            Text(session.userResult).foregroundStyle(session.resultColor)
                            Text("·")
                            Text(session.createdAt, format: .dateTime.year().month().day().hour().minute()).foregroundStyle(.secondary)
                        }.font(.callout)
                    }
                    Spacer(minLength: 12)
                    Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
                }.padding(24)
                HStack {
                    Picker(Messages.SessionUI.session.localized, selection: $tab) {
                        Text(Messages.SessionUI.overview.localized).tag(Tab.overview)
                        Text(Messages.SessionUI.console.localized).tag(Tab.console)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 200)
                    Spacer()
                    Button { exporting = true } label: { Label(Messages.SessionUI.exportReport.localized, systemImage: "square.and.arrow.up") }
                }.padding(.horizontal, 24).padding(.bottom, 16)
                Divider()
                Group {
                    switch tab {
                    case .overview: GameDiagnosticView(session: session, action: diagnosticAction).id(session.id)
                    case .console: GameConsoleView(session: session).id(session.id)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !session.state.isFinished {
                    Divider()
                    if GameMonitorClient.activity(session) == .monitoring {
                        GameQuitControls(session: session).padding(.horizontal, 24).padding(.vertical, 14)
                    } else {
                        GameSessionRecoveryView(session: session).id(session.id).padding(16)
                    }
                }
            } else {
                HStack { Spacer(); Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
                if let error {
                    ContentUnavailableView(Messages.SessionUI.session.localized, systemImage: "exclamationmark.triangle", description: Text(error))
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .frame(width: 860, height: 680)
        .sheet(isPresented: $exporting) { if let session { GameReportExportView(session: session).id(session.id) } }
        .sheet(item: $destination) { target in
            if let session, let instance = model.state.instances.first(where: { $0.id == session.instanceID }) {
                switch target {
                case .settings: InstanceSettingsView(instance: instance)
                case .mods: InstanceContentView(instance: instance)
                }
            }
        }
        .task(id: model.requestedLogSessionID) {
            loaded = nil; error = nil; tab = .overview; exporting = false; destination = nil
            guard let id = model.requestedLogSessionID else { return }
            if let session { model.acknowledgeSession(session); return }
            let paths = model.paths
            do {
                let value = try await Task.detached(priority: .utility) { try GameHistoryStore.load(paths: paths, sessionID: id) }.value
                try Task.checkCancellation(); loaded = value
                if let loaded { model.acknowledgeSession(loaded) }
                else { error = Messages.SessionUI.recordUnavailable.localized }
            } catch { self.error = error.localizedDescription }
        }
        .onChange(of: session?.state) {
            if let session { model.acknowledgeSession(session) }
        }
    }
    private func diagnosticAction(_ action: GameDiagnosis.Action) {
        guard let session else { return }
        switch action {
        case .collect: exporting = true
        case .files:
            if let directory = try? GameSessionStore.directory(paths: model.paths, instanceID: session.instanceID, sessionID: session.id) {
                let target = FileManager.default.fileExists(atPath: directory.path) ? directory : (session.gameDirectory ?? model.paths.game(session.instanceID))
                NSWorkspace.shared.activateFileViewerSelecting([target])
            }
        case .settings: destination = .settings
        case .mods: destination = .mods
        case .accounts: model.page = .accounts; dismiss()
        case .repair:
            if let instance = model.state.instances.first(where: { $0.id == session.instanceID }) { model.repair(instance) }
        }
    }
}
