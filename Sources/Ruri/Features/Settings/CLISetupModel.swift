import AppKit
import Observation
import RuriCore
import RuriLocalization

@MainActor @Observable final class CLISetupModel {
    static let onboardingSeenKey = "RuriCLIOnboardingSeen"
    static let helpCommand = "ruri --help"

    private(set) var installed = false
    private(set) var owned = false
    private(set) var legacyLink: String?
    private(set) var link = ""
    private(set) var working = false
    private(set) var issue: String?
    var copied = false
    var ready: Bool { installed && legacyLink == nil }
    var repair: Bool { owned || legacyLink != nil }
    private let installation: CLIInstallation?

    init(installation: CLIInstallation? = nil) {
        self.installation = installation
        refresh()
    }

    func copyHelpCommand() {
        Self.copy(Self.helpCommand)
        copied = true
    }

    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    func refresh() {
        do {
            let status = try (installation ?? CLIInstallation()).status()
            installed = status["installed"].bool ?? false
            owned = status["owned"].bool ?? false
            legacyLink = status["legacyLink"].string
            link = status["link"].string ?? ""
        } catch { issue = error.localizedDescription }
    }

    func change(_ action: CLIInstallation.Action) {
        guard !working else { return }
        working = true; issue = nil; copied = false
        Task {
            defer { working = false; refresh() }
            do {
                let service = try installation ?? CLIInstallation()
                do {
                    _ = try await Task.detached(priority: .userInitiated) {
                        if action == .install { try service.install() } else { try service.uninstall() }
                    }.value
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
