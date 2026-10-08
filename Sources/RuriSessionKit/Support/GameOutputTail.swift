import Foundation
import Darwin

/// A byte budget, not a line budget: even an unterminated line cannot grow it.
package struct GameOutputTail {
    private var bytes: [UInt8]
    private var next = 0
    package private(set) var count = 0
    package private(set) var truncated = false

    package init(capacity: Int = 262_144, truncated: Bool = false) { precondition(capacity > 0); bytes = .init(repeating: 0, count: capacity); self.truncated = truncated }

    package mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let capacity = bytes.count
        truncated = truncated || data.count > capacity - count
        data.withUnsafeBytes { input in
            bytes.withUnsafeMutableBytes { output in
                if data.count >= capacity {
                    memcpy(output.baseAddress!, input.baseAddress!.advanced(by: data.count - capacity), capacity)
                    next = 0
                } else {
                    let first = min(data.count, capacity - next)
                    memcpy(output.baseAddress!.advanced(by: next), input.baseAddress!, first)
                    if first < data.count { memcpy(output.baseAddress!, input.baseAddress!.advanced(by: first), data.count - first) }
                    next = (next + data.count) % capacity
                }
            }
        }
        count = min(capacity, count + data.count)
    }

    package func snapshot(final: Bool) -> Data {
        var result = Data()
        result.reserveCapacity(count)
        let start = count == bytes.count ? next : 0
        let first = min(count, bytes.count - start)
        result.append(contentsOf: bytes[start..<(start + first)])
        if first < count { result.append(contentsOf: bytes[..<(count - first)]) }
        // Never expose a credential fragment at a truncated line boundary.
        if truncated {
            guard let newline = result.firstIndex(of: 10) else { return Data() }
            result.removeSubrange(...newline)
        }
        if !final {
            guard let newline = result.lastIndex(of: 10) else { return Data() }
            result.removeSubrange(result.index(after: newline)...)
        }
        return result
    }
}
