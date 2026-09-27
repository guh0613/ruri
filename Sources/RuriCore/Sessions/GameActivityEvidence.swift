import Foundation

struct QuickPlayVisit: Equatable, Sendable {
    let target: GameActivityTarget
    let date: Date
    static func read(_ data: Data, startedAt: Date, now: Date) -> QuickPlayVisit? {
        guard data.count <= 65536, let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.count == 1,
              let row = rows.first, let kind = row["type"] as? String, let identifier = row["id"] as? String,
              let name = row["name"] as? String, name.utf8.count <= 1024, let stamp = row["lastPlayedTime"] as? String else { return nil }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date: Date?
        if let parsed = formatter.date(from: stamp) { date = parsed }
        else { formatter.formatOptions = [.withInternetDateTime]; date = formatter.date(from: stamp) }
        guard let date, date >= startedAt, date <= now.addingTimeInterval(5) else { return nil }
        let target: GameActivityTarget
        switch kind {
        case "singleplayer": target = .world(folder: identifier, name: name)
        case "multiplayer":
            guard let address = try? ServerAddress(identifier) else { return nil }
            target = .server(address: address, name: name)
        case "realms": target = .unattributed
        default: return nil
        }
        guard target.valid else { return nil }
        return .init(target: target, date: date)
    }
}

enum GameActivityLogEvent: Sendable {
    case connecting(ServerAddress)
    case left(explicit: Bool)
    case legacyJoined
}

struct GameActivityLogParser {
    private var decoder = GameOutputDecoder(omitted: "")
    let version: String
    mutating func reset() { decoder = GameOutputDecoder(omitted: "") }
    mutating func consume(_ data: Data) -> [GameActivityLogEvent] {
        decoder.consume(data).components(separatedBy: .newlines).compactMap { line in
            // Anchored client-thread messages only. Chat text and arbitrary
            // occurrences of these strings must never become control events.
            if line.range(of: #"^(?:\[[0-9:]+\] )?\[Server thread/INFO\](?: \[[^\]]+\])?:? Starting integrated minecraft server"#, options: .regularExpression) != nil { return .left(explicit: false) }
            let pattern = #"^(?:\[[0-9:]+\] )?\[(?:Render thread|Client thread)/(?:INFO|WARN|ERROR)\](?: \[[^\]]+\])?:? (.*)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { return nil }
            let body = String(line[range])
            if body.hasPrefix("Connecting to "), let comma = body.lastIndex(of: ",") {
                let host = String(body.dropFirst(14).prefix(upTo: comma)).trimmingCharacters(in: .whitespaces)
                let port = String(body[body.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
                let authority = (host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host) + ":" + port
                return (try? ServerAddress(authority)).map(GameActivityLogEvent.connecting)
            }
            if body.hasPrefix("Starting integrated minecraft server") { return .left(explicit: false) }
            if body == "Stopping!" || body.hasPrefix("Disconnected from server:") || body.hasPrefix("Lost connection:") { return .left(explicit: true) }
            // Vanilla 1.12–1.19 logs this after receiving an advancement packet
            // in the play state. It only confirms an already pending connection.
            if version.range(of: #"^1\.(?:1[2-9])(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
               body.range(of: #"^Loaded [0-9]+ advancements$"#, options: .regularExpression) != nil { return .legacyJoined }
            return nil
        }
    }
}

/// A bounded byte tap independent of the console's rotating presentation tail.
/// Sequence gaps invalidate attribution instead of silently missing a disconnect.
final class GameActivityLogFeed: @unchecked Sendable {
    struct Chunk: Sendable { let sequence: UInt64; let data: Data? }
    let stream: AsyncStream<Chunk>
    private let continuation: AsyncStream<Chunk>.Continuation
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    init() {
        let pair = AsyncStream<Chunk>.makeStream(bufferingPolicy: .bufferingNewest(16))
        stream = pair.stream; continuation = pair.continuation
    }
    func receive(_ data: Data) {
        lock.lock(); sequence &+= 1
        continuation.yield(.init(sequence: sequence, data: data.count <= 131072 ? data : nil))
        lock.unlock()
    }
    func finish() { continuation.finish() }
}
