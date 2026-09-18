import SwiftUI

/// Keep recent page data across view recreation without retaining every page visited.
@MainActor final class ViewSnapshotCache<Key: Hashable, Value> {
    private let capacity: Int
    private var values: [Key: Value] = [:]
    private var order: [Key] = []

    init(capacity: Int = 16) { self.capacity = capacity }

    subscript(key: Key) -> Value? {
        get {
            guard let value = values[key] else { return nil }
            order.removeAll { $0 == key }
            order.append(key)
            return value
        }
        set {
            values[key] = newValue
            order.removeAll { $0 == key }
            if newValue != nil { order.append(key) }
            while order.count > capacity { values.removeValue(forKey: order.removeFirst()) }
        }
    }
}

/// Fast local reads should finish before a spinner ever becomes visible.
struct DelayedProgressView: View {
    @State private var visible = false

    var body: some View {
        ProgressView()
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(!visible)
            .task {
                visible = false
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    try Task.checkCancellation()
                    visible = true
                } catch {}
            }
    }
}
