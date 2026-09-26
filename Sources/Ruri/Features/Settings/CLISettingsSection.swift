import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CLISettingsSection: View {
    @State private var installed = false
    @State private var onPath = false
    @State private var link = ""
    @State private var issue: String?
    var body: some View {
        Section {
            HStack {
                Text(Messages.CLIInterface.ta3dc8fc730b8.localized)
                Spacer()
                Button(installed ? Messages.CLIInterface.t06bc14b60f35.localized : Messages.CLIInterface.te8f88f51ccb0.localized) { changeInstallation() }
            }
            if !link.isEmpty { Text(link).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            if installed && !onPath {
                Text(Messages.CLIInterface.t20255da83a92.localized)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Button(Messages.CLIInterface.t80cc6a4f6c96.localized) {
                if let executable = RuriInstallation.cliExecutable {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(executable.path, forType: .string)
                }
            }
        } header: { Text(Messages.CLIInterface.t56f8e5b9417c.localized) } footer: {
            Text(Messages.CLIInterface.t9401df17eb2f.localized)
        }
        .task { refresh() }
    }
    private func refresh() {
        do {
            let status = try CLIInstallation().status()
            installed = status["installed"].bool ?? false; onPath = status["onPath"].bool ?? false
            link = status["link"].string ?? ""
        } catch { issue = error.localizedDescription }
    }
    private func changeInstallation() {
        do {
            let service = try CLIInstallation()
            if installed { _ = try service.uninstall() } else { _ = try service.install() }
            issue = nil; refresh()
        } catch { issue = error.localizedDescription }
    }
}
