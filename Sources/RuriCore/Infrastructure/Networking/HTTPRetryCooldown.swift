import Foundation

/// Shared only by one update check. Sleeping requests remain cancellable and
/// do not cause other workers to keep requesting a host during its cooldown.
actor HTTPRetryCooldown {
    private var deadlines: [String: ContinuousClock.Instant] = [:]

    func wait(for host: String) async throws {
        while let deadline = deadlines[host], deadline > .now {
            try Task.checkCancellation()
            try await Task.sleep(until: deadline, clock: .continuous)
        }
        try Task.checkCancellation()
    }
    func postpone(_ host: String, seconds: Double) {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        if deadline > (deadlines[host] ?? .now) { deadlines[host] = deadline }
    }
    static func delay(for response: HTTPURLResponse) -> Double {
        let retry = response.value(forHTTPHeaderField: "Retry-After")
        if let retry, let seconds = Double(retry), seconds.isFinite, seconds >= 0 { return max(1, seconds) }
        if let retry {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = formatter.date(from: retry) { return max(1, date.timeIntervalSinceNow) }
        }
        if let value = response.value(forHTTPHeaderField: "X-Ratelimit-Reset"),
           let seconds = Double(value), seconds.isFinite, seconds >= 0 { return max(1, seconds + 1) }
        return 60
    }
}
