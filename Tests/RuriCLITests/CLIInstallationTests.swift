import Foundation
import Testing
import RuriCore

struct CLIInstallationTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri terminal \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("ruri-cli")
        try Data("#!/bin/sh\nprintf '%s\\n' \"$@\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return (root, executable)
    }
    @Test func standardDirectoryDoesNotDependOnTheGUIPath() throws {
        let (root, executable) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(try CLIInstallation(executable: executable).link.path == "/usr/local/bin/ruri")
        let service = try CLIInstallation(executable: executable, binDirectory: root.appendingPathComponent("bin"))
        _ = try service.install()
        let status = service.status(environment: ["PATH": "/usr/bin:/bin"])
        #expect(status["installed"] == .bool(true))
        #expect(status["onPath"] == .bool(false))
    }
    @Test func protectedDirectoryReportsAuthorizationBeforeWriting() throws {
        let (root, executable) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bin.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path) }
        let service = try CLIInstallation(executable: executable, binDirectory: bin)
        #expect(try service.install(dryRun: true)["status"]["requiresAuthorization"] == .bool(true))
        do { _ = try service.install(); Issue.record("Expected authorization") }
        catch let error as OperationFailure { #expect(error.code == "AUTHORIZATION_REQUIRED") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path).isEmpty)
    }
    @Test func currentProtectedInstallNeedsNoNewAuthorizationAndUninstallStillDoes() throws {
        let (root, executable) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin"), lock = bin.appendingPathComponent(".ruri-cli-install.lock")
        let service = try CLIInstallation(executable: executable, binDirectory: bin)
        _ = try service.install()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bin.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: lock.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lock.path)
        }
        #expect(try service.install()["changed"] == .bool(false))
        do { _ = try service.uninstall(); Issue.record("Expected authorization") }
        catch let error as OperationFailure { #expect(error.code == "AUTHORIZATION_REQUIRED") }
        #expect(FileManager.default.fileExists(atPath: service.link.path))
    }
    @Test func legacyMigrationFindsMovedAppAndOnlyRemovesOwnedLink() throws {
        let (root, executable) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home"), bin = home.appendingPathComponent(".local/bin")
        let old = try CLIInstallation(executable: executable, binDirectory: bin, homeDirectory: home)
        _ = try old.install()
        let moved = root.appendingPathComponent("moved-cli")
        try FileManager.default.moveItem(at: executable, to: moved)
        let service = try CLIInstallation(executable: moved, homeDirectory: home)
        #expect(service.status()["legacyLink"] == .string(old.link.path))
        try service.removeLegacyLink()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: old.link.path)) == nil)
        try Data("user command".utf8).write(to: old.link)
        try service.removeLegacyLink()
        #expect(try Data(contentsOf: old.link) == Data("user command".utf8))
    }
    @Test func authorizationArgumentsAndAppleScriptCannotInterpretPathCharacters() throws {
        let (root, executable) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let strange = root.appendingPathComponent("quote ' double \" $HOME $(echo unexpected) `echo unexpected` \\ end")
        try FileManager.default.createDirectory(at: strange, withIntermediateDirectories: true)
        let moved = strange.appendingPathComponent("ruri-cli")
        try FileManager.default.moveItem(at: executable, to: moved)
        let bin = strange.appendingPathComponent("bin")
        let service = try CLIInstallation(executable: moved, binDirectory: bin)
        let (code, output) = try ProcessRunner.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", service.authorizationCommand(.uninstall)])
        #expect(code == 0)
        #expect(output == ["cli", "uninstall", "--bin-dir", bin.path, "--json", "--quiet", "--yes", ""].joined(separator: "\n"))
        let command = service.authorizationCommand(.install)
        let result = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", "return " + CLIInstallation.appleScriptString(command)])
        #expect(result.0 == 0 && result.1 == command + "\n")
        let compiled = try ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osacompile"), arguments: ["-o", root.appendingPathComponent("authorization.scpt").path, "-e", service.authorizationScript(.install)])
        #expect(compiled.0 == 0, "\(compiled.1)")
    }
}
