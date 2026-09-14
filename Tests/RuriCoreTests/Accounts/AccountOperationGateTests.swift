import Foundation
import Testing
@testable import RuriCore

struct AccountOperationGateTests {
    @Test(.timeLimit(.minutes(1))) @MainActor func serializesSameAccountAndCancellationDoesNotBlockQueue() async throws {
        let gate = AccountOperationGate(), id = UUID()
        var events: [String] = []
        var releaseFirst: CheckedContinuation<Void, Never>?
        let first = Task { @MainActor in
            try await gate.withLock(for: id) {
                events.append("first-start")
                await withCheckedContinuation { releaseFirst = $0 }
                events.append("first-end")
            }
        }
        while releaseFirst == nil { await Task.yield() }
        let cancelled = Task { @MainActor in try await gate.withLock(for: id) { events.append("cancelled") } }
        let next = Task { @MainActor in try await gate.withLock(for: id) { events.append("next") } }
        try await gate.withLock(for: UUID()) { events.append("independent") }
        cancelled.cancel()
        releaseFirst?.resume()
        try await first.value; try await next.value
        do { try await cancelled.value; Issue.record("Cancelled waiter ran") } catch is CancellationError {} catch { throw error }
        #expect(events == ["first-start", "independent", "first-end", "next"])
        try await gate.withLock(for: id) { events.append("reused") }
        #expect(events.last == "reused")
    }
    @Test @MainActor func thrownOperationReleasesTheAccount() async throws {
        let gate = AccountOperationGate(), id = UUID()
        await #expect(throws: (any Error).self) {
            try await gate.withLock(for: id) { throw URLError(.notConnectedToInternet) }
        }
        let value = try await gate.withLock(for: id) { 42 }
        #expect(value == 42)
    }
}
