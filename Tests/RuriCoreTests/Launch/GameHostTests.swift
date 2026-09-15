import Foundation
import Testing
@testable import RuriCore

struct GameHostTests {
    @Test(.timeLimit(.minutes(1))) @MainActor func nativeLibrariesCannotRebaseRelativePathsIntoTheHostBundle() async throws {
        let (root, plan) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("directory.c")
        try Data(#"""
        #include <CoreFoundation/CoreFoundation.h>
        #include <errno.h>
        #include <fcntl.h>
        #include <limits.h>
        #include <stdio.h>
        #include <string.h>
        #include <unistd.h>
        int JLI_Launch(int argc, char **argv, int a, const char **b, int c, const char **d,
                      const char *e, const char *f, const char *g, const char *h,
                      unsigned char i, unsigned char j, unsigned char k, int l) {
            char before[PATH_MAX], after[PATH_MAX], resources[PATH_MAX];
            if (!getcwd(before, sizeof(before))) return 10;
            CFURLRef url = CFBundleCopyResourcesDirectoryURL(CFBundleGetMainBundle());
            if (!url || !CFURLGetFileSystemRepresentation(url, true, (UInt8 *)resources, sizeof(resources))) return 11;
            CFRelease(url);
            // Reproduce the real GLFW 3.2 initialization behavior.
            if (chdir(resources) || !getcwd(after, sizeof(after)) || strcmp(before, after)) return 12;
            int fd = open(resources, O_RDONLY);
            if (fd < 0 || fchdir(fd) || !getcwd(after, sizeof(after)) || strcmp(before, after)) return 13;
            close(fd);
            FILE *file = fopen("relative-file", "w");
            if (!file) return 14;
            fputs("game directory", file); fclose(file);
            if (chdir("bin") || !getcwd(after, sizeof(after)) || !strcmp(before, after)) return 15;
            errno = 0;
            if (chdir("missing-directory") != -1 || errno != ENOENT) return 16;
            return 0;
        }
        """#.utf8).write(to: source)
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-dynamiclib", "-framework", "CoreFoundation", source.path, "-o", root.appendingPathComponent("lib/libjli.dylib").path]
        try compiler.run(); compiler.waitUntilExit(); #expect(compiler.terminationStatus == 0)
        let game = GameProcess(), capture = try GameOutputCapture(redactor: .init())
        let exit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, Error>) in
            do { try game.start(plan: plan, capture: capture, hostExecutable: TestPaths.gameHostExecutable) { continuation.resume(returning: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        #expect(exit.status == 0)
        #expect(game.hostStatus?.jvmStarted == true)
        #expect(try String(contentsOf: root.appendingPathComponent("relative-file"), encoding: .utf8) == "game directory")
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func monitorAcceptsTheCurrentHostProtocol() async throws {
        let (paths, instance) = try GameSessionTests().setup()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let recorder = try GameSessionRecorder(paths: paths, instance: instance, accountMode: "offline")
        var settings = MacOSGameSettings(); settings.enabled = false
        var plan = LaunchPlan(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "exit 0"], directory: paths.game(instance.id), environment: ["PATH": "/usr/bin:/bin"])
        plan.host = .init(instanceID: instance.id, name: instance.name, iconPNG: nil, javaVersion: "21", architecture: "aarch64", settings: settings, fullscreen: false)
        try await GameMonitorClient.start(plan: plan, recorder: recorder, paths: paths, secrets: [], helper: TestPaths.monitorExecutable)
        let finished = try await GameMonitorClient.wait(paths: paths, instanceID: instance.id, sessionID: recorder.record.id)
        #expect(finished.state == .succeeded && finished.host?.fallback == "disabled")
    }

    @Test func settingsPreserveInheritanceAndPortableSnapshots() throws {
        var defaults = AppSettings()
        var settings = MacOSGameSettings(); settings.enabled = false; settings.nativeFullscreen = false
        defaults.defaultMacOSGameSettings = settings
        var instance = GameInstance(name: "Game", gameVersion: "1.21.1"); instance.launchOverrides = .init()
        #expect(try instance.launchSnapshot(defaults: defaults).macOSGameSettings == settings)
        instance.launchOverrides?.macOS = .init()
        let snapshot = try instance.launchSnapshot(defaults: defaults)
        #expect(snapshot.macOSGameSettings?.enabled == true)
        let exported = try JSONDecoder().decode(PortableInstance.self, from: JSONEncoder().encode(PortableInstance(snapshot)))
        #expect(try exported.instance().macOSGameSettings == snapshot.macOSGameSettings)
        #expect(try JSONDecoder().decode(MacOSGameSettings.self, from: Data("{}".utf8)) == .init())
    }

    @Test func framedEventsHandlePartialReadsAndRejectOversizedFrames() throws {
        let sessionID = UUID()
        let payload = try JSONSerialization.data(withJSONObject: ["version": 1, "sessionID": sessionID.uuidString, "pid": 42, "event": "windowReady"])
        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }; frame.append(payload)
        var decoder = GameHostEventDecoder()
        #expect(try decoder.append(frame.prefix(2)).isEmpty)
        #expect(try decoder.append(frame.dropFirst(2).prefix(5)).isEmpty)
        let events = try decoder.append(Data(frame.dropFirst(7)) + frame)
        #expect(events.count == 2 && events.allSatisfy { $0.sessionID == sessionID && $0.event == "windowReady" })
        #expect(throws: (any Error).self) { try decoder.append(Data([0, 2, 0, 0])) }
    }

    private func fixture() throws -> (URL, LaunchPlan) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ruri-host-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("lib"), withIntermediateDirectories: true)
        let java = root.appendingPathComponent("bin/java")
        try Data("#!/bin/sh\nprintf 'direct-pid=%s\\n' \"$$\"\nprintf '%s\\n' \"$@\"\nexit 9\n".utf8).write(to: java)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: java.path)
        #if arch(arm64)
        let architecture = "aarch64"
        #else
        let architecture = "x86_64"
        #endif
        var plan = LaunchPlan(executable: java, arguments: ["Main", "space and 中文", "--fullscreen", "fixture-secret"], directory: root, environment: ["PATH": "/usr/bin:/bin"])
        plan.host = .init(instanceID: UUID(), name: "实例", iconPNG: nil, javaVersion: "21", architecture: architecture, settings: .init(), fullscreen: true)
        return (root, plan)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func unavailableJLIExecutesJavaInTheSameProcessAndPreservesArguments() async throws {
        let (root, plan) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a dylib".utf8).write(to: root.appendingPathComponent("lib/libjli.dylib"))
        let game = GameProcess()
        var redactor = GameLogRedactor(); redactor.addSecrets(["fixture-secret"])
        let capture = try GameOutputCapture(redactor: redactor)
        let exit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, Error>) in
            do { try game.start(plan: plan, capture: capture, hostExecutable: TestPaths.gameHostExecutable) { continuation.resume(returning: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        #expect(exit.status == 9 && !exit.stopRequested)
        #expect(game.hostStatus?.backend == .java && game.hostStatus?.fallback == "runtimeLoad")
        #expect(game.hostStatus?.jvmStarted == false)
        let output = capture.snapshot(final: true)
        #expect(output.contains("direct-pid=\(exit.processID)"))
        #expect(output.contains("space and 中文") && output.contains("--fullscreen"))
        #expect(output.contains("<redacted>") && !output.contains("fixture-secret"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("launch.json").path))
    }

    @Test(.timeLimit(.minutes(1))) @MainActor func jvmFailureNeverRetriesJava() async throws {
        let (root, plan) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("jli.c")
        try Data(#"""
        #include <stdio.h>
        #include <unistd.h>
        int JLI_Launch(int argc, char **argv, int a, const char **b, int c, const char **d,
                      const char *e, const char *f, const char *g, const char *h,
                      unsigned char i, unsigned char j, unsigned char k, int l) {
            printf("jvm-pid=%d\n", getpid());
            for (int n = 1; n < argc; n++) printf("%s\n", argv[n]);
            return 7;
        }
        """#.utf8).write(to: source)
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-dynamiclib", source.path, "-o", root.appendingPathComponent("lib/libjli.dylib").path]
        try compiler.run(); compiler.waitUntilExit(); #expect(compiler.terminationStatus == 0)
        let game = GameProcess()
        let capture = try GameOutputCapture(redactor: .init())
        let exit = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<GameExit, Error>) in
            do { try game.start(plan: plan, capture: capture, hostExecutable: TestPaths.gameHostExecutable) { continuation.resume(returning: $0) } }
            catch { continuation.resume(throwing: error) }
        }
        #expect(exit.status == 7 && game.hostStatus?.backend == .native && game.hostStatus?.jvmStarted == true)
        let output = capture.snapshot(final: true)
        #expect(output.contains("jvm-pid=\(exit.processID)"))
        #expect(output.contains("space and 中文") && !output.contains("--fullscreen") && !output.contains("direct-pid"))
    }
}
