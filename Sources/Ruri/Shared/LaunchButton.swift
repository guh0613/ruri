import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct LaunchButton: View {
    @Environment(AppModel.self) private var model
    let instance: GameInstance
    var size: ControlSize = .regular
    /// Icon-only form for compact rows: a plain accent-colored circle instead of a filled button.
    var compact = false
    private var session: GameSession? { model.activeSessions[instance.id] }
    private var title: String {
        if session != nil { return session?.gameIdentity?.isAlive == true ? Messages.AppLaunchButton.returnToGame.localized : Messages.AppLaunchButton.viewRunHistory.localized }
        return instance.installed ? Messages.AppLaunchButton.launchGame.localized : Messages.AppLaunchButton.continueInstallation.localized
    }
    private var disabled: Bool { session == nil && (model.busy || model.isInstanceInUse(instance.id)) }
    private func activate() { if session != nil { model.returnToGame(instance.id) } else { model.launch(instance) } }
    var body: some View {
        if compact {
            Button(action: activate) {
                Image(systemName: session != nil ? "arrow.up.forward.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(disabled ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Theme.accent))
                    .accessibilityLabel(title)
            }.buttonStyle(.plain).help(title).disabled(disabled)
        } else {
            Button(action: activate) {
                Label(title, systemImage: session != nil ? "arrow.up.forward.app" : "play.fill").padding(.horizontal, 6)
            }.buttonStyle(.borderedProminent).controlSize(size).help(title).disabled(disabled)
        }
    }
}
