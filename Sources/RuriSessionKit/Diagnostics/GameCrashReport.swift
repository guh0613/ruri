import RuriLocalization
import Foundation

public struct GameCrashReport: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case minecraft = "Minecraft", jvm
        public var title: String { switch self { case .minecraft: "Minecraft"; case .jvm: Messages.CoreGameExit.javaVirtualMachine.localized } }
    }
    public let url: URL
    public let kind: Kind
    public var id: String { url.path }

    /// Only associate files from this launch; previous reports must not diagnose a later exit.
    public static func find(in game: URL, exit: GameExit) -> [GameCrashReport] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        var candidates: [(URL, Kind)] = []
        if (try? game.appendingPathComponent("crash-reports").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
           let directory = try? SessionFileSystem.safePath("crash-reports", within: game),
           let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) {
            candidates += files.filter { $0.lastPathComponent.hasPrefix("crash-") && $0.pathExtension == "txt" }.map { ($0, .minecraft) }
        }
        let jvmName = "hs_err_pid\(exit.processID).log"
        if (try? game.appendingPathComponent(jvmName).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
           let jvm = try? SessionFileSystem.safePath(jvmName, within: game) { candidates.append((jvm, .jvm)) }
        return candidates.compactMap { url, kind -> GameCrashReport? in
            guard let attributes = try? url.resourceValues(forKeys: keys), attributes.isRegularFile == true,
                  attributes.isSymbolicLink == false, let modified = attributes.contentModificationDate,
                  modified >= exit.startedAt, modified <= exit.endedAt.addingTimeInterval(5) else { return nil }
            return GameCrashReport(url: url, kind: kind)
        }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }
}
