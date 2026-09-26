import RuriLocalization
import Foundation

public enum RuriInstallation {
    public static func application(executable: URL? = Bundle.main.executableURL) -> URL? {
        guard let executable else { return nil }
        var parent = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            if parent.pathExtension == "app", let bundle = Bundle(url: parent), bundle.bundleIdentifier == "dev.ruri.launcher" { return parent }
            parent.deleteLastPathComponent()
        }
        return nil
    }
    public static var info: [String: Any] { application().flatMap { Bundle(url: $0)?.infoDictionary } ?? Bundle.main.infoDictionary ?? [:] }
    public static var cliExecutable: URL? {
        if let app = application() { return app.appendingPathComponent("Contents/Helpers/ruri-cli") }
        return Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent().appendingPathComponent("ruri-cli")
    }
    public static func resourceBundle(_ name: String) -> Bundle? {
        if let app = application(), let bundle = Bundle(url: app.appendingPathComponent("Contents/Resources/\(name).bundle")) { return bundle }
        guard let binary = Bundle.main.executableURL?.resolvingSymlinksInPath() else { return nil }
        return Bundle(url: binary.deletingLastPathComponent().appendingPathComponent("\(name).bundle"))
    }
}

public struct CLIInstallation: Sendable {
    public let executable: URL
    public let binDirectory: URL
    public var link: URL { binDirectory.appendingPathComponent("ruri") }
    private var receipt: URL { binDirectory.appendingPathComponent(".ruri-cli-install.json") }
    public init(executable: URL? = RuriInstallation.cliExecutable, binDirectory: URL? = nil) throws {
        guard let executable else { throw OperationFailure("CLI_UNAVAILABLE", Messages.CLIInterface.t53102783ab6d.localized) }
        self.executable = executable.resolvingSymlinksInPath()
        self.binDirectory = (binDirectory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin")).standardizedFileURL
    }
    private var destination: String? { try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) }
    private var owned: Bool {
        guard let destination else { return false }
        if destination == executable.path { return true }
        guard let data = try? Data(contentsOf: receipt), let prior = try? JSONDecoder().decode(String.self, from: data) else { return false }
        return destination == prior
    }
    public func status(environment: [String: String] = ProcessInfo.processInfo.environment) -> OperationValue {
        .object(["executable": .string(executable.path), "link": .string(link.path), "target": .text(destination),
                 "installed": .bool(owned && destination == executable.path && FileManager.default.isExecutableFile(atPath: executable.path)),
                 "owned": .bool(owned), "onPath": .bool((environment["PATH"] ?? "").split(separator: ":").contains { URL(fileURLWithPath: String($0)).standardizedFileURL == binDirectory })])
    }
    public func install(dryRun: Bool = false) throws -> OperationValue {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw OperationFailure("CLI_UNAVAILABLE", Messages.CLIInterface.tcef88e8371f1.localized) }
        func validate() throws {
            if (FileManager.default.fileExists(atPath: link.path) || destination != nil) && !owned {
                throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.t93432f8e8264.localized, details: .object(["path": .string(link.path)]))
            }
        }
        try validate()
        if dryRun { return .object(["dryRun": .bool(true), "changed": .bool(destination != executable.path), "status": status()]) }
        let lease = try OperationLease.acquire(directory: binDirectory, name: ".ruri-cli-install.lock")
        defer { withExtendedLifetime(lease) {} }
        try validate()
        let changed = destination != executable.path
        if changed {
            let temporary = binDirectory.appendingPathComponent(".ruri-link-\(UUID())")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try FileManager.default.createSymbolicLink(atPath: temporary.path, withDestinationPath: executable.path)
            // rename replaces only the directory entry, never a symlink target.
            guard rename(temporary.path, link.path) == 0 else { throw OperationFailure("IO_ERROR", Messages.CLIInterface.t301c72c06b6d.localized) }
        }
        try JSONEncoder().encode(executable.path).write(to: receipt, options: .atomic)
        return .object(["changed": .bool(changed), "status": status()])
    }
    public func uninstall(dryRun: Bool = false) throws -> OperationValue {
        let exists = FileManager.default.fileExists(atPath: link.path) || destination != nil
        guard !exists || owned else { throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.t93432f8e8264.localized) }
        guard !dryRun, exists else { return .object(["changed": .bool(exists), "dryRun": .bool(dryRun), "status": status()]) }
        let lease = try OperationLease.acquire(directory: binDirectory, name: ".ruri-cli-install.lock")
        defer { withExtendedLifetime(lease) {} }
        guard owned else { throw OperationFailure("PATH_CONFLICT", Messages.CLIInterface.te99b33ffd7c8.localized) }
        try FileManager.default.removeItem(at: link)
        if FileManager.default.fileExists(atPath: receipt.path) { try FileManager.default.removeItem(at: receipt) }
        return .object(["changed": .bool(true), "status": status()])
    }
}
