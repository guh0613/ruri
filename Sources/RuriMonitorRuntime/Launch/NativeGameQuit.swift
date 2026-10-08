import AppKit
import Foundation
import RuriLocalization

public enum NativeGameQuit {
    /// An accepted request is not an exit acknowledgement. Cocoa/GLFW may
    /// decline or defer it; only the process owner records the eventual exit.
    @MainActor public static func request(_ identity: ProcessIdentity) -> Bool {
        guard identity.isAlive,
              let application = NSRunningApplication(processIdentifier: identity.pid), !application.isTerminated, application.activationPolicy != .prohibited,
              identity.isAlive else { return false }
        return application.terminate()
    }
}
