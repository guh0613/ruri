import Foundation
import RuriLocalization

public struct ContentUpdateCheckProgress: Sendable {
    public let completed: Int
    public let total: Int
}

public struct ContentUpdateCheckFailure: Sendable {
    public let record: ManagedContent
    public let message: String
    let underlying: any Error
}

public struct ContentUpdateCheckResult: Sendable {
    public var modrinth: [ContentUpdate] = []
    public var curseforge: [CurseForgeUpdate] = []
    public var failures: [ContentUpdateCheckFailure] = []
    public var failureDescription: String? {
        guard !failures.isEmpty else { return nil }
        var lines = failures.prefix(3).map { Messages.ContentDetails.updateFailure($0.record.title, $0.message).localized }
        if failures.count > 3 { lines.append(Messages.ContentDetails.updateFailuresRemaining(Int64(failures.count - 3)).localized) }
        return lines.joined(separator: "\n")
    }
}

/// Both providers share one bounded queue. Requests finish independently and
/// results retain input order, so latency does not change the update selection.
public struct ContentUpdateChecker: Sendable {
    private let modrinth: ModrinthService
    private let curseforge: CurseForgeService?
    public init(modrinth: ModrinthService = ModrinthService(), curseforge: CurseForgeService? = nil) {
        self.modrinth = modrinth; self.curseforge = curseforge
    }
    private enum Update: Sendable {
        case modrinth(ContentUpdate)
        case curseforge(CurseForgeUpdate)
    }
    @concurrent public func check(_ records: [ManagedContent], instance: GameInstance,
                      progress: @escaping @Sendable (ContentUpdateCheckProgress) async -> Void = { _ in }) async throws -> ContentUpdateCheckResult {
        let records = records.filter { ["modrinth", "curseforge"].contains($0.provider) }
        var unavailable: [String: any Error] = [:]
        if curseforge == nil { unavailable["curseforge"] = RuriError.message(Messages.CoreCurseForge.apiKeyRequired) }
        let checked = try await ContentUpdateQueries.run(records, unavailable: unavailable, progress: progress) { record -> Update? in
            if record.provider == "modrinth" {
                return try await modrinth.update(for: record, instance: instance).map(Update.modrinth)
            }
            guard let curseforge else { return nil }
            return try await curseforge.update(for: record, instance: instance).map(Update.curseforge)
        }
        var result = ContentUpdateCheckResult(failures: checked.failures)
        for update in checked.updates {
            switch update {
            case .modrinth(let value): result.modrinth.append(value)
            case .curseforge(let value): result.curseforge.append(value)
            }
        }
        return result
    }
}

enum ContentUpdateQueries {
    struct Result<Update: Sendable>: Sendable {
        var updates: [Update] = []
        var failures: [ContentUpdateCheckFailure] = []
    }
    private struct Outcome<Update: Sendable>: Sendable {
        let index: Int
        var update: Update? = nil
        var failure: ContentUpdateCheckFailure? = nil
    }

    @concurrent static func run<Update: Sendable>(_ input: [ManagedContent], unavailable: [String: any Error] = [:],
                                     progress: @escaping @Sendable (ContentUpdateCheckProgress) async -> Void = { _ in },
                                     query: @escaping @Sendable (ManagedContent) async throws -> Update?) async throws -> Result<Update> {
        try Task.checkCancellation()
        var seen = Set<String>()
        let records = input.filter { seen.insert($0.id).inserted }
        let cooldown = HTTPRetryCooldown()
        await progress(.init(completed: 0, total: records.count))
        return try await withThrowingTaskGroup(of: Outcome<Update>.self) { group in
            var next = 0, completed = 0
            var unavailable = unavailable
            var outcomes: [Outcome<Update>] = []
            outcomes.reserveCapacity(records.count)
            // Enqueue only as slots become available; never spawn one task per file.
            func enqueue() throws {
                while next < records.count {
                    try Task.checkCancellation()
                    let index = next, record = records[index]; next += 1
                    if let error = unavailable[record.provider] {
                        outcomes.append(.init(index: index, failure: .init(record: record, message: error.localizedDescription, underlying: error)))
                        completed += 1
                        continue
                    }
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let update = try await HTTPClient.$retryCooldown.withValue(cooldown) { try await query(record) }
                            try Task.checkCancellation()
                            return .init(index: index, update: update)
                        } catch {
                            if Task.isCancelled || error is CancellationError { throw CancellationError() }
                            return .init(index: index, failure: .init(record: record, message: error.localizedDescription, underlying: error))
                        }
                    }
                    return
                }
            }
            for _ in 0..<6 { try enqueue() }
            await progress(.init(completed: completed, total: records.count))
            while let outcome = try await group.next() {
                try Task.checkCancellation()
                outcomes.append(outcome); completed += 1
                if let failure = outcome.failure, let response = failure.underlying as? RuriError,
                   let status = response.httpStatusCode, [401, 403, 429].contains(status) {
                    // Do not keep sending a provider the rest of the queue after
                    // it rejects authorization or asks us to stop requesting.
                    unavailable[failure.record.provider] = response
                }
                try enqueue()
                await progress(.init(completed: completed, total: records.count))
            }
            try Task.checkCancellation()
            var result = Result<Update>()
            for outcome in outcomes.sorted(by: { $0.index < $1.index }) {
                if let update = outcome.update { result.updates.append(update) }
                if let failure = outcome.failure { result.failures.append(failure) }
            }
            return result
        }
    }
}
