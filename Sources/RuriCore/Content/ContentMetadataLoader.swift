import Foundation

/// Enriches a directory snapshot without holding the content-operation lock.
public enum ContentMetadataLoader {
    @concurrent public static func enrich(_ files: [LocalContentFile], cacheDirectory: URL,
                              receive: @escaping @Sendable ([LocalContentFile]) async -> Void) async {
        let pending = files.filter { !$0.metadataLoaded }
        guard !pending.isEmpty, !Task.isCancelled else { return }
        let cache = LocalContentMetadataCache.shared(in: cacheDirectory)
        defer { cache.flush() }
        // Small chunks cap open archives and memory, and return early visible results.
        await withTaskGroup(of: [LocalContentFile].self) { group in
            var next = 0
            func enqueue() {
                guard next < pending.count, !Task.isCancelled else { return }
                let batch = Array(pending[next..<min(next + 8, pending.count)])
                next += batch.count
                group.addTask {
                    var result: [LocalContentFile] = []
                    for file in batch {
                        guard !Task.isCancelled else { break }
                        guard let stamp = file.stamp, let entry = cache.resolve(file.url, stamp: stamp, kind: file.kind) else { continue }
                        result.append(file.presenting(entry.metadata, pack: entry.pack, identities: entry.identities ?? [], loaded: true))
                    }
                    return result
                }
            }
            for _ in 0..<4 { enqueue() }
            var buffered: [LocalContentFile] = []
            var lastDelivery = ContinuousClock.now
            for await batch in group {
                if Task.isCancelled { group.cancelAll(); break }
                buffered.append(contentsOf: batch)
                if buffered.count >= 32 || lastDelivery.duration(to: .now) >= .milliseconds(100) {
                    await receive(buffered); buffered.removeAll(keepingCapacity: true); lastDelivery = .now
                }
                enqueue()
            }
            if !buffered.isEmpty, !Task.isCancelled { await receive(buffered) }
        }
    }
}
