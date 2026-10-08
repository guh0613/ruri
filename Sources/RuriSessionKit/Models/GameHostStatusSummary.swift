import Foundation
import RuriLocalization

extension GameHostStatus {
    public var summary: String {
        if let failure { return Messages.GameHost.failed(Self.explanation(failure)).localized }
        if backend == .java { return Messages.GameHost.compatibility(Self.explanation(fallback ?? "disabled")).localized }
        if fullscreen { return Messages.GameHost.fullscreen.localized }
        if windowReadyAt != nil { return Messages.GameHost.windowReady.localized }
        return jvmStarted ? Messages.GameHost.jvmStarting.localized : Messages.GameHost.starting.localized
    }
    static func explanation(_ code: String) -> String {
        switch code {
        case "disabled": Messages.GameHost.disabled.localized
        case "wrapper": Messages.GameHost.wrapper.localized
        case "architecture": Messages.GameHost.architecture.localized
        case "hostMissing": Messages.GameHost.hostMissing.localized
        case "runtimeMissing", "runtimeLoad", "runtimeEntry": Messages.GameHost.runtimeUnavailable.localized
        case "directory": Messages.GameHost.directory.localized
        case "javaExec": Messages.GameHost.javaExec.localized
        case "transport": Messages.GameHost.transport.localized
        default: Messages.GameHost.invalidRequest.localized
        }
    }
}
