import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

/// One run, told as a player would read it: what was played, for how long, and
/// how it ended. The raw log is a level deeper, behind its own screen, and
/// report export stays a deliberate step rather than a competing mode.
struct LogsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private enum Destination: String, Identifiable { case settings, mods; var id: String { rawValue } }
    @State private var showingConsole = false
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
        ZStack {
            if let session {
                detail(session)
                if showingConsole {
                    console(session)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .zIndex(1)
                }
            } else {
                placeholder
            }
        }
        .background(Theme.canvas(for: colorScheme))
        // Fixed, and sized so a normal run fills it exactly; a diagnosis with
        // suggestions scrolls rather than growing the window.
        .frame(width: 880, height: 640)
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
            loaded = nil; error = nil; showingConsole = false; exporting = false; destination = nil
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

    private var doneButton: some View {
        Button(Messages.Common.done.localized) { dismiss() }.keyboardShortcut(.cancelAction)
    }

    private var placeholder: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); doneButton }.padding(24)
            Group {
                if let error {
                    ContentUnavailableView(Messages.SessionUI.session.localized, systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Overview

    /// The run's identity is the title of the sheet; there is no separate
    /// title bar, so the page starts with the icon and the name.
    private func detail(_ session: GameSession) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero(session)
                    facts(session)
                    GameDiagnosticView(session: session, action: diagnosticAction).id(session.id)
                    tools(session)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            if !session.state.isFinished {
                Divider()
                if GameMonitorClient.activity(session) == .monitoring {
                    GameQuitControls(session: session).padding(.horizontal, 24).padding(.vertical, 14)
                } else {
                    GameSessionRecoveryView(session: session).id(session.id).padding(16)
                }
            }
        }
    }

    /// The raw log, slid in over the overview with a way back, in place of a
    /// navigation bar the sheet has no room for.
    private func console(_ session: GameSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { showingConsole = false }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.body.weight(.semibold))
                        Text(session.instanceName).lineLimit(1)
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                Spacer()
                doneButton
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)
            Divider()
            GameConsoleView(session: session).id(session.id)
        }
        .background(Theme.canvas(for: colorScheme))
    }

    private func hero(_ session: GameSession) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if let instance = model.state.instances.first(where: { $0.id == session.instanceID }) {
                InstanceIcon(instance, size: 64)
            } else {
                InstanceIcon(loader: LoaderKind(rawValue: session.loader) ?? .vanilla, size: 64)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(session.instanceName).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                HStack(spacing: 8) {
                    Label(session.userResult, systemImage: session.resultSymbol)
                        .font(.callout.weight(.medium)).foregroundStyle(session.resultColor)
                    Text("·").foregroundStyle(.secondary)
                    Text(LocalizedFormat.date(session.startDate)).font(.callout).foregroundStyle(.secondary)
                }
                if let world = session.world {
                    Label(world.name, systemImage: "map").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            doneButton
        }
    }

    private func facts(_ session: GameSession) -> some View {
        Surface {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 3), alignment: .leading, spacing: 18) {
                StatTile(label: Messages.SessionUI.duration.localized, value: session.userDuration)
                StatTile(label: Messages.SessionUI.started.localized, value: LocalizedFormat.date(session.startDate, date: .omitted, time: .standard))
                StatTile(label: Messages.SessionUI.ended.localized,
                         value: session.endDate.map { LocalizedFormat.date($0, date: .omitted, time: .standard) } ?? "—")
                StatTile(label: Messages.HistoryUI.world.localized, value: session.world?.name ?? Messages.HistoryUI.unknownWorld.localized)
                StatTile(label: "Minecraft", value: session.gameVersion)
                StatTile(label: Messages.HistoryUI.loader.localized,
                         value: (LoaderKind(rawValue: session.loader)?.title ?? session.loader) + (session.loaderVersion.map { " " + $0 } ?? ""))
                StatTile(label: "Java", value: session.java ?? "—")
                StatTile(label: Messages.HistoryUI.memory.localized, value: LocalizedFormat.bytes(Int64(session.memoryMB) * 1_048_576, memory: true))
                StatTile(label: Messages.SessionUI.environment.localized, value: session.hostArchitecture)
            }
        }
    }

    /// The professional end of the screen. Everything here leaves this page.
    private func tools(_ session: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(Messages.HistoryUI.moreTools.localized)
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    ActionRow(symbol: "apple.terminal", tint: .gray, title: Messages.HistoryUI.openLogs.localized,
                              detail: Messages.HistoryUI.openLogsHelp.localized) {
                        withAnimation(.easeInOut(duration: 0.25)) { showingConsole = true }
                    }
                    Divider().padding(.leading, 62)
                    ActionRow(symbol: "square.and.arrow.up", tint: .blue, title: Messages.SessionUI.exportReport.localized,
                              detail: Messages.SessionUI.reportHelp.localized) { exporting = true }
                    if model.state.instances.contains(where: { $0.id == session.instanceID }) {
                        Divider().padding(.leading, 62)
                        ActionRow(symbol: "folder", tint: .orange, title: Messages.SessionUI.openGameFolder.localized,
                                  detail: Messages.SessionRuntime.loggingHelp.localized) { diagnosticAction(.files) }
                    }
                }
            }
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
