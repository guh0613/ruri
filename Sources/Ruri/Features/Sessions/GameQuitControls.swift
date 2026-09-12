import RuriLocalization
import SwiftUI
import RuriCore

struct GameQuitControls: View {
    @Environment(AppModel.self) private var model
    let session: GameSession
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if session.stage == .beforeCommand || session.stage == .afterCommand {
                HStack {
                    Text(session.stage == .beforeCommand ? Messages.AppGameQuitControls.cancelWillStop.localized : Messages.AppGameQuitControls.gameExited.localized).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(Messages.AppGameQuitControls.cancelCommand.localized) { model.confirmGameTermination(session.instanceID) }
                }
            } else {
            if let attempt = session.normalQuitAttempt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attempt.explanation).font(.caption).foregroundStyle(.secondary)
                        if attempt.accepted && context.date.timeIntervalSince(attempt.processedAt) >= 20 {
                            Text(Messages.AppGameQuitControls.gameStillRunning.localized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if session.nativeQuitSupported != true {
                Text(Messages.AppGameQuitControls.normalExitNotice.localized).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(Messages.AppGameQuitControls.returnToGame.localized) { model.returnToGame(session.instanceID) }.disabled(session.gameIdentity?.isAlive != true)
                Spacer()
                if session.nativeQuitSupported == true {
                    Button(session.normalQuitAttempt?.accepted == true ? Messages.AppGameQuitControls.requestExitAgain.localized : Messages.AppGameQuitControls.requestNormalExit.localized) { model.requestGameQuit(session.instanceID) }
                        .disabled(session.gameIdentity?.isAlive != true || session.stage == .stopping)
                }
                Menu {
                    Button(Messages.AppGameQuitControls.terminateProcess.localized, role: .destructive) { model.confirmGameTermination(session.instanceID) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help(Messages.AppGameQuitControls.unresponsiveGameAction.localized)
            }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
