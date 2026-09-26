import RuriLocalization
import SwiftUI
import AppKit
import RuriCore

struct CLISettingsSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var installed = false
    @State private var owned = false
    @State private var legacyLink: String?
    @State private var link = ""
    @State private var working = false
    @State private var issue: String?
    @State private var copied = false
    private var ready: Bool { installed && legacyLink == nil }
    private var repair: Bool { owned || legacyLink != nil }
    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: ready ? "checkmark.circle.fill" : repair ? "wrench.and.screwdriver" : "terminal")
                    .font(.title2).foregroundStyle(ready ? Color.green : Color.accentColor)
                    .padding(.top, 2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(ready ? Messages.CLISetup.ready.localized : repair ? Messages.CLISetup.repairTitle.localized : Messages.CLISetup.title.localized)
                        .font(.headline)
                    Text(ready ? Messages.CLISetup.readyDetail.localized : repair ? Messages.CLISetup.repairDetail.localized : Messages.CLISetup.introduction.localized)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if working { ProgressView().controlSize(.small) }
                else if !ready {
                    Button(repair ? Messages.CLISetup.repair.localized : Messages.CLISetup.install.localized) { change(.install) }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(.vertical, 4)
            if ready {
                HStack {
                    Text(verbatim: "ruri --help").font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    Spacer()
                    Button(copied ? Messages.CLISetup.copied.localized : Messages.CLISetup.copyCommand.localized) {
                        copy("ruri --help"); copied = true
                    }
                }
            }
            if let issue { Text(issue).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            DisclosureGroup(Messages.CLISetup.details.localized) {
                VStack(alignment: .leading, spacing: 16) {
                    if !link.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Messages.CLISetup.location.localized)
                                .font(.caption).foregroundStyle(.secondary)
                            Text(verbatim: link)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Button(Messages.CLISetup.copyDirectCommand.localized) {
                                if let executable = RuriInstallation.cliExecutable { copy(CLIInstallation.shellQuote(executable.path) + " --help") }
                            }
                            if ready { Button(Messages.CLISetup.reinstall.localized) { change(.install) } }
                            if owned || legacyLink != nil {
                                Button(Messages.CLIInterface.t06bc14b60f35.localized, role: .destructive) { change(.uninstall) }
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
        } header: { Text(Messages.CLIInterface.t56f8e5b9417c.localized) } footer: {
            Text(Messages.CLISetup.footer.localized)
        }
        .disabled(working)
        .task { refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active && !working { refresh() } }
    }
    private func copy(_ command: String) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
    }
    private func refresh() {
        do {
            let status = try CLIInstallation().status()
            installed = status["installed"].bool ?? false; owned = status["owned"].bool ?? false
            legacyLink = status["legacyLink"].string; link = status["link"].string ?? ""
        } catch { issue = error.localizedDescription }
    }
    private func change(_ action: CLIInstallation.Action) {
        working = true; issue = nil; copied = false
        Task {
            defer { working = false; refresh() }
            do {
                let service = try CLIInstallation()
                do {
                    if action == .install { _ = try service.install() } else { _ = try service.uninstall() }
                } catch let failure as OperationFailure where failure.code == "AUTHORIZATION_REQUIRED" {
                    try await Self.authorize(service, action: action)
                    try service.removeLegacyLink()
                }
            } catch is CancellationError { }
            catch { issue = error.localizedDescription }
        }
    }
    private static func authorize(_ service: CLIInstallation, action: CLIInstallation.Action) async throws {
        let script = service.authorizationScript(action)
        let (status, data) = try await Task.detached(priority: .userInitiated) {
            let process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output; process.standardError = output
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, data)
        }.value
        let message = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if message == "__RURI_AUTH_CANCELLED__" { throw CancellationError() }
        guard status == 0, let result = try? JSONDecoder().decode(OperationValue.self, from: data) else {
            throw OperationFailure("AUTHORIZATION_FAILED", Messages.CLISetup.authorizationFailed(message).localized)
        }
        if result["ok"] != .bool(true) { throw try result["error"].decode(OperationFailure.self) }
    }
}
