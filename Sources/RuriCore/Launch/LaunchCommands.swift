import RuriLocalization
import Foundation

public struct LaunchCommands: Codable, Equatable, Sendable {
    public var enabled = false
    public var before = ""
    public var after = ""
    public var wrapper = ""
    public var timeoutSeconds = 300
    public init() {}
    public var isEmpty: Bool { [before, after, wrapper].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    public func validate() throws {
        guard (1...3600).contains(timeoutSeconds), [before, after, wrapper].allSatisfy({ $0.utf8.count <= 32768 && !$0.contains("\0") }) else {
            throw RuriError.message(Messages.CoreLaunchCommands.invalidCommand)
        }
        if enabled { _ = try ArgumentTokenizer.split(wrapper) }
    }
    func resolveWrapper(environment: [String: String], directory: URL) throws -> [String] {
        guard enabled else { return [] }
        let pattern = try NSRegularExpression(pattern: #"\$\{(RURI_[A-Z_]+)\}"#)
        var tokens = try ArgumentTokenizer.split(wrapper).map { token in
            var result = token
            for match in pattern.matches(in: token, range: NSRange(token.startIndex..., in: token)).reversed() {
                guard let keyRange = Range(match.range(at: 1), in: token), let range = Range(match.range, in: result) else { continue }
                let key = String(token[keyRange])
                guard let value = environment[key] else { throw RuriError.message(Messages.CoreLaunchCommands.unsupportedVariable(String(describing: key))) }
                result.replaceSubrange(range, with: value)
            }
            return result
        }
        guard let program = tokens.first else { return [] }
        let candidates: [URL]
        if program.contains("/") { candidates = [program.hasPrefix("/") ? URL(fileURLWithPath: program) : directory.appendingPathComponent(program).standardizedFileURL] }
        else {
            candidates = (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":", omittingEmptySubsequences: false).map { component in
                let folder = component.hasPrefix("/") ? URL(fileURLWithPath: String(component)) : directory.appendingPathComponent(String(component))
                return folder.appendingPathComponent(program).standardizedFileURL
            }
        }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { throw RuriError.message(Messages.CoreLaunchCommands.executableMissing(String(describing: program))) }
        tokens[0] = executable.path
        return tokens
    }
}

public struct GameCommandResult: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case before, after
        public var title: String { message.localized }
        public var message: LocalizedMessage { self == .before ? Messages.CoreLaunchCommands.beforeLaunchCommand : Messages.CoreLaunchCommands.afterExitCommand }
    }
    public let phase: Phase
    public let startedAt: Date
    public let endedAt: Date
    public let status: Int32?
    public let cancelled: Bool
    public let timedOut: Bool
    public let error: String?
    public var errorMessage: LocalizedMessage? = nil
    public var succeeded: Bool { status == 0 && !cancelled && !timedOut && error == nil }
    public var summary: String { summaryMessage.localized }
    public var summaryMessage: LocalizedMessage {
        let result: LocalizedMessage
        if timedOut { result = Messages.CoreLaunchCommands.commandTimedOut(phase.title) }
        else if cancelled { result = Messages.CoreLaunchCommands.commandCancelled(phase.title) }
        else if let error {
            let failure = Messages.CoreLaunchCommands.commandFailed(phase.title, error)
            result = errorMessage.map { failure.withTextArgument(1, message: $0) } ?? failure
        } else if status == 0 { result = Messages.CoreLaunchCommands.commandCompleted(phase.title) }
        else { result = Messages.CoreLaunchCommands.commandExitStatus(phase.title, status.map(String.init) ?? Messages.CoreLaunchCommands.unknownResult.localized) }
        return result.withTextArgument(0, message: phase.message)
    }
}
