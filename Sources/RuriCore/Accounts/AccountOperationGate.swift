import Foundation

/// Serializes refreshes and authenticated requests for each account. Tokens
/// refreshed by one operation are visible before the next reads the keychain.
@MainActor public final class AccountOperationGate {
    private struct Waiter { let token: UUID; let continuation: CheckedContinuation<Void, Never> }
    private var owners: [UUID: UUID] = [:]
    private var waiters: [UUID: [Waiter]] = [:]
    public init() {}

    public func withLock<T>(for account: UUID, operation: @MainActor () async throws -> T) async throws -> T {
        let token = UUID()
        try Task.checkCancellation()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if owners[account] == nil { owners[account] = token; continuation.resume() }
                else { waiters[account, default: []].append(.init(token: token, continuation: continuation)) }
            }
        } onCancel: {
            Task { @MainActor in self.cancelWaiter(account: account, token: token) }
        }
        defer { release(account: account, token: token) }
        try Task.checkCancellation()
        return try await operation()
    }
    private func cancelWaiter(account: UUID, token: UUID) {
        guard let index = waiters[account]?.firstIndex(where: { $0.token == token }) else { return }
        waiters[account]?.remove(at: index).continuation.resume()
    }
    private func release(account: UUID, token: UUID) {
        guard owners[account] == token else { return }
        if var queued = waiters[account], !queued.isEmpty {
            let next = queued.removeFirst(); waiters[account] = queued.isEmpty ? nil : queued
            owners[account] = next.token; next.continuation.resume()
        } else { owners[account] = nil; waiters[account] = nil }
    }
}
