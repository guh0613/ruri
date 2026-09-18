import SwiftUI
import AppKit
import RuriCore
import RuriLocalization

struct GameDiagnosticView: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    let action: (GameDiagnosis.Action) -> Void
    @State private var diagnosis: GameDiagnosis?
    @State private var analyzing = false
    @State private var error: String?
    private var key: String { "\(session.id)-\(session.state.rawValue)-\(session.evidence.count)-\(session.artifactState?.rawValue ?? "")" }
    private var instanceAvailable: Bool { model.state.instances.contains { $0.id == session.instanceID } }

    /// The written explanation for one run. Its container owns the scroll view,
    /// the run's own numbers and the tools that leave this screen.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(session.overviewHelp)
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if session.timing?.quality == .interrupted {
                Label(Messages.SessionRuntime.timingPartial.localized, systemImage: "clock.badge.questionmark").font(.callout).foregroundStyle(.secondary)
            }
            if session.hasPostCommandFailure {
                Button(Messages.CoreGameDiagnosis.checkInstanceSettings.localized) { action(.settings) }.disabled(!instanceAvailable)
            } else if session.needsAttention { suggestions }
            if session.artifactState == .expired {
                Label(Messages.SessionRuntime.artifactsExpired.localized, systemImage: "archivebox").font(.callout).foregroundStyle(.secondary)
            }
            technicalDetails
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: key) {
            diagnosis = nil; error = nil
            guard session.needsAttention, !session.hasPostCommandFailure else { return }
            analyzing = true; defer { analyzing = false }
            let paths = model.paths, record = session
            let work = Task.detached(priority: .utility) { try GameDiagnosticAnalyzer.load(paths: paths, session: record, includeGameLogs: true) }
            do {
                let value = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation(); diagnosis = value
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    @ViewBuilder private var suggestions: some View {
        if analyzing { ProgressView(Messages.AppGameDiagnosticView.readingEvidence.localized).controlSize(.small) }
        else if let diagnosis, !diagnosis.findings.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(Messages.SessionUI.suggestions.localized).font(.headline)
                ForEach(Array(diagnosis.findings.prefix(3))) { finding in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(finding.title).font(.headline)
                        Text(finding.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(finding.steps.prefix(3).enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).").foregroundStyle(.secondary).monospacedDigit()
                                Text(step).fixedSize(horizontal: false, vertical: true)
                            }.font(.callout)
                        }
                        HStack {
                            ForEach(Array(finding.actions.filter { $0 != .collect && $0 != .files }.prefix(2)), id: \.self) { item in
                                Button(item.title) { action(item) }
                                    .disabled(!instanceAvailable || (item == .repair && (model.busy || model.isInstanceInUse(session.instanceID))))
                            }
                        }.controlSize(.small)
                        DisclosureGroup(Messages.SessionUI.evidence.localized) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(finding.confidence.title).font(.caption).foregroundStyle(.secondary)
                                ForEach(finding.evidence) { evidence in
                                    Text(evidence.excerpt).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.padding(.top, 8)
                        }.font(.caption)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(Messages.SessionUI.noFinding.localized).font(.headline)
                Text(diagnosis?.summary ?? session.displayFailure ?? Messages.SessionUI.noFindingHelp.localized)
                    .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
    private var technicalDetails: some View {
        DisclosureGroup(Messages.SessionUI.technicalDetails.localized) {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                    detail(Messages.SessionUI.started.localized, (session.timing?.startedAt ?? session.exit?.startedAt ?? session.createdAt).formatted(date: .abbreviated, time: .standard))
                    if let exit = session.exit { detail(Messages.SessionUI.ended.localized, exit.endedAt.formatted(date: .abbreviated, time: .standard)) }
                    detail(Messages.SessionUI.environment.localized, "\(session.loader) \(session.loaderVersion ?? "") · \(session.hostArchitecture)")
                    detail("Java", session.java ?? "—")
                    detail("macOS", session.operatingSystem)
                    if let world = session.world { detail(Messages.HistoryUI.world.localized, world.name + " · " + world.folder) }
                    if let host = session.host { detail(Messages.SessionUI.result.localized, host.summary) }
                    if let exit = session.exit { detail(Messages.SessionUI.result.localized, exit.logDescription) }
                }.textSelection(.enabled)
                Text(Messages.SessionRuntime.timingHelp.localized).foregroundStyle(.secondary)
                if session.needsAttention {
                    Button(Messages.SessionUI.openSystemReports.localized) {
                        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") { NSWorkspace.shared.open(app) }
                    }
                }
                Divider()
                ForEach(session.events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.date, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(.secondary)
                        Text(event.displayMessage).textSelection(.enabled)
                    }
                }
                if let diagnosis, !diagnosis.limitations.isEmpty {
                    Text(Messages.SessionUI.collectingLimits.localized).fontWeight(.medium)
                    ForEach(diagnosis.limitations, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
            }.font(.caption).padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout)
    }
    private func detail(_ title: String, _ value: String) -> some View {
        GridRow(alignment: .top) {
            Text(title).foregroundStyle(.secondary).fixedSize()
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
