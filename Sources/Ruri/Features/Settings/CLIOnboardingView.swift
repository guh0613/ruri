import RuriLocalization
import SwiftUI

struct CLIOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State var setup = CLISetupModel()

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: setup.ready ? "checkmark.circle.fill" : "terminal")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(setup.ready ? Color.green : Color.accentColor)
                    .frame(height: 48)
                    .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(setup.ready ? Messages.CLISetup.ready.localized : Messages.CLISetup.onboardingTitle.localized)
                        .font(.title2.weight(.semibold))
                    Text(setup.ready ? Messages.CLISetup.readyDetail.localized : Messages.CLISetup.onboardingDetail.localized)
                        .font(.callout).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            if setup.ready {
                HStack(spacing: 12) {
                    Text(verbatim: CLISetupModel.helpCommand)
                        .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button { setup.copyHelpCommand() } label: {
                        Label(setup.copied ? Messages.CLISetup.copied.localized : Messages.CLISetup.copyCommand.localized,
                              systemImage: setup.copied ? "checkmark" : "doc.on.doc")
                    }
                    .labelStyle(.iconOnly)
                    .help(setup.copied ? Messages.CLISetup.copied.localized : Messages.CLISetup.copyCommand.localized)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Text(Messages.CLISetup.onboardingHint.localized)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let issue = setup.issue {
                ScrollView {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
            }

            HStack(spacing: 10) {
                if setup.working { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                if setup.ready {
                    Button(Messages.Common.done.localized) { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(Messages.CLISetup.skip.localized) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button(setup.working ? Messages.CLISetup.installing.localized : setup.repair ? Messages.CLISetup.repair.localized : Messages.CLISetup.install.localized) {
                        setup.change(.install)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .disabled(setup.working)
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .interactiveDismissDisabled(setup.working)
        .onChange(of: scenePhase) {
            if scenePhase == .active && !setup.working { setup.refresh() }
        }
    }
}
