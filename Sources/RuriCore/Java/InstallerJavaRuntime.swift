import Foundation
import RuriLocalization

/// A UI may provide an interactive resolver for an installation operation.
/// Core/CLI callers without one receive an actionable error, never a download.
/// Task-local scope also covers pack imports and component changes that create
/// their own installer services while keeping unrelated operations independent.
public enum InstallerJavaRuntime {
    public typealias Request = @Sendable (_ minimumMajor: Int, _ component: String) async throws -> JavaRuntime
    @TaskLocal public static var request: Request?

    static func resolve(minimumMajor: Int, component: String, paths: LauncherPaths) async throws -> JavaRuntime {
        try await resolve(minimumMajor: minimumMajor, component: component, from: JavaDiscovery.scan(paths: paths))
    }

    static func resolve(minimumMajor: Int, component: String, from runtimes: [JavaRuntime]) async throws -> JavaRuntime {
        try Task.checkCancellation()
        if let existing = JavaDiscovery.selectForInstallation(from: runtimes, minimumMajor: minimumMajor) { return existing }
        guard let request else {
            throw RuriError.message(Messages.CoreInstallerJavaRuntime.javaRequired(component, String(minimumMajor)))
        }
        let java = try await request(minimumMajor, component)
        try Task.checkCancellation()
        guard JavaDiscovery.selectForInstallation(from: [java], minimumMajor: minimumMajor) != nil else {
            throw RuriError.message(Messages.CoreInstallerJavaRuntime.javaRequired(component, String(minimumMajor)))
        }
        return java
    }
}
