import RuriLocalization
import SwiftUI
import RuriCore

struct GameSessionRecoveryView: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    @State private var current: GameSession?
    @State private var status: GameSessionRecovery.Status = .monitoring
    @State private var instanceLocked = false
    @State private var confirmedEnded = false
    @State private var working = false
    @State private var error: String?
    @State private var refreshError: String?
    init(session: GameSession) {
        self.session = session
        _current = State(initialValue: session)
        _status = State(initialValue: GameSessionRecovery.status(session))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Keep a mounted host for the polling task even while a healthy
            // monitor needs no visible recovery controls.
            Color.clear.frame(height: 0)
            if status != .finished && status != .monitoring {
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.title).font(.headline)
                    Text(status.explanation).font(.callout).fixedSize(horizontal: false, vertical: true)
                    if status == .confirmationRequired {
                        Toggle(Messages.AppGameSessionRecoveryView.gameExitConfirmed.localized, isOn: $confirmedEnded).toggleStyle(.checkbox)
                        Text(Messages.AppGameSessionRecoveryView.recoveryDetails.localized).font(.caption).foregroundStyle(.secondary)
                    }
                    if instanceLocked { Text(Messages.AppGameSessionRecoveryView.instanceBusy.localized).font(.caption).foregroundStyle(.secondary) }
                    if let message = error ?? refreshError { Text(message).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    HStack {
                        Button(Messages.AppGameSessionRecoveryView.refreshStatus.localized) { Task { await refresh() } }.disabled(working)
                        if status == .gameRunning { Button(Messages.AppGameSessionRecoveryView.returnToGame.localized) { model.returnToGame(session.instanceID) } }
                        Spacer()
                        if working { ProgressView().controlSize(.small) }
                        if status == .processEnded || status == .confirmationRequired {
                            Button(Messages.AppGameSessionRecoveryView.finalizeAndResume.localized) { recover() }.buttonStyle(.borderedProminent)
                                .disabled(working || model.busy || instanceLocked || (status == .confirmationRequired && !confirmedEnded))
                        }
                    }
                }.padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            } else if let message = error ?? refreshError { Text(message).font(.callout).foregroundStyle(.orange) }
        }
        .task(id: session.id) {
            while !Task.isCancelled {
                await refresh()
                if status == .finished { return }
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
    }
    private func refresh() async {
        guard !working else { return }
        let paths = model.paths, instanceID = session.instanceID, sessionID = session.id
        let work = Task.detached(priority: .utility) {
            let record = try GameSessionStore.load(paths: paths, instanceID: instanceID, sessionID: sessionID)
            return (record, GameSessionRecovery.status(record), GameRunLease.isHeld(paths: paths, instanceID: instanceID))
        }
        do {
            let result = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
            try Task.checkCancellation()
            if current != result.0 || status != result.1 { confirmedEnded = false }
            current = result.0; status = result.1; instanceLocked = result.2; refreshError = nil
        } catch { if !Task.isCancelled { self.refreshError = error.localizedDescription } }
    }
    private func recover() {
        guard let current else { return }
        let paths = model.paths, confirmed = confirmedEnded
        working = true; error = nil
        Task {
            defer { working = false }
            do {
                let result = try await Task.detached { try GameSessionRecovery.finish(paths: paths, expected: current, userConfirmedEnded: confirmed) }.value
                self.current = result; status = .finished
                await model.didRecoverSession(result)
            } catch {
                self.error = error.localizedDescription
                working = false
                await refresh()
            }
        }
    }
}
