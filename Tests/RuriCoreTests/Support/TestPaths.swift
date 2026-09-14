import Foundation

/// SwiftPM places executable products beside the test bundle. Derive this from
/// the loaded bundle so moving a test or using another scratch path still works.
enum TestPaths {
    static var gameHostExecutable: URL {
        if let path = ProcessInfo.processInfo.environment["RURI_TEST_GAME_HOST"] { return URL(fileURLWithPath: path) }
        return monitorExecutable.deletingLastPathComponent().appendingPathComponent("RuriGame.app/Contents/MacOS/ruri-game")
    }
    static var monitorExecutable: URL {
        Bundle(for: TestBundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("ruri-monitor")
    }
}

private final class TestBundleMarker: NSObject {}
