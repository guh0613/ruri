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
                    Text(session.stage == .beforeCommand ? Messages.AppGameQuitControls.bodyText1.localized : Messages.AppGameQuitControls.bodyText2.localized).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(Messages.AppGameQuitControls.bodyText3.localized) { model.confirmGameTermination(session.instanceID) }
                }
            } else {
            if let attempt = session.normalQuitAttempt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(attempt.explanation).font(.caption).foregroundStyle(.secondary)
                        if attempt.accepted && context.date.timeIntervalSince(attempt.processedAt) >= 20 {
                            Text(Messages.AppGameQuitControls.attemptText1.localized).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if session.nativeQuitSupported != true {
                Text(Messages.AppGameQuitControls.attemptText2.localized).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(Messages.AppGameQuitControls.attemptText3.localized) { model.returnToGame(session.instanceID) }.disabled(session.gameIdentity?.isAlive != true)
                Spacer()
                if session.nativeQuitSupported == true {
                    Button(session.normalQuitAttempt?.accepted == true ? Messages.AppGameQuitControls.attemptText4.localized : Messages.AppGameQuitControls.attemptText5.localized) { model.requestGameQuit(session.instanceID) }
                        .disabled(session.gameIdentity?.isAlive != true || session.stage == .stopping)
                }
                Menu {
                    Button(Messages.AppGameQuitControls.attemptText6.localized, role: .destructive) { model.confirmGameTermination(session.instanceID) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help(Messages.AppGameQuitControls.attemptText7.localized)
            }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
