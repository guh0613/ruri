import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CLISettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var setup = CLISetupModel()
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: setup.ready ? "checkmark.circle.fill" : setup.repair ? "wrench.and.screwdriver" : "terminal")
                    .font(.title2).foregroundStyle(setup.ready ? Color.green : Color.accentColor)
                    .padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(setup.packageManager.map { Messages.CLISetup.provided($0).localized }
                         ?? (setup.ready ? Messages.CLISetup.ready.localized : setup.repair ? Messages.CLISetup.repairTitle.localized : Messages.CLISetup.title.localized))
                        .font(.headline)
                    Text(setup.ready ? Messages.CLISetup.readyDetail.localized : setup.repair ? Messages.CLISetup.repairDetail.localized : Messages.CLISetup.introduction.localized)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if setup.working { ProgressView().controlSize(.small) }
                else if !setup.ready {
                    Button(setup.repair ? Messages.CLISetup.repair.localized : Messages.CLISetup.install.localized) { setup.change(.install) }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(.vertical, 4)
            if setup.ready {
                HStack {
                    Text(verbatim: CLISetupModel.helpCommand).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(setup.copied ? Messages.CLISetup.copied.localized : Messages.CLISetup.copyCommand.localized) {
                        setup.copyHelpCommand()
                    }
                }
            }
            if let issue = setup.issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            // A package manager provides ruri, so only Ruri's earlier links are left to remove.
            if setup.packageManager == nil || setup.repair { details }
        } header: { Text(Messages.CLIInterface.commandLineAndAutomationTitle.localized) } footer: {
            Text(Messages.CLISetup.footer.localized)
        }
        .disabled(setup.working)
        .task { setup.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active && !setup.working { setup.refresh() } }
    }

    /// Under a package manager, the link shown is the earlier one left to remove.
    private var location: String {
        setup.packageManager == nil || setup.owned ? setup.link : setup.legacyLink ?? setup.link
    }

    private var details: some View {
        DisclosureGroup(Messages.CLISetup.details.localized) {
            VStack(alignment: .leading, spacing: 16) {
                if !location.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Messages.CLISetup.location.localized)
                            .font(.caption).foregroundStyle(.secondary)
                        Text(verbatim: location)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        if setup.packageManager == nil {
                            Button(Messages.CLISetup.copyDirectCommand.localized) {
                                if let executable = RuriInstallation.cliExecutable { CLISetupModel.copy(CLIInstallation.shellQuote(executable.path) + " --help") }
                            }
                            if setup.ready { Button(Messages.CLISetup.reinstall.localized) { setup.change(.install) } }
                        }
                        if setup.owned || setup.legacyLink != nil {
                            Button(Messages.CLIInterface.uninstallAction.localized, role: .destructive) { setup.change(.uninstall) }
                        }
                    }
                    .controlSize(.small)
                    Text(Messages.CLISetup.authorizationHint.localized)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }
}
