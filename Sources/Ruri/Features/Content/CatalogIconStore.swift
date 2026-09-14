import Foundation
import ImageIO

/// CGImage is immutable. Decode it on a worker before passing it to AppKit.
struct CatalogIconAsset: @unchecked Sendable {
    let thumbnail: CGImage?
    let original: Data?

    var memoryCost: Int {
        if let thumbnail { return thumbnail.bytesPerRow * thumbnail.height }
        return original?.count ?? 0
    }
}

actor CatalogIconStore {
    static let shared = CatalogIconStore()
    private final class Entry: NSObject {
        let asset: CatalogIconAsset
        init(_ asset: CatalogIconAsset) { self.asset = asset }
    }
    private let cache = NSCache<NSURL, Entry>()
    private var inFlight: [URL: Task<CatalogIconAsset?, Never>] = [:]

    private init() {
        cache.totalCostLimit = 24 * 1024 * 1024
        cache.countLimit = 256
    }

    func image(at url: URL) async -> CatalogIconAsset? {
        if let cached = cache.object(forKey: url as NSURL) { return cached.asset }
        if let pending = inFlight[url] { return await pending.value }

        // A shared request survives one disappearing cell and can serve the
        // same icon in the grid, list, project header, and install sheet.
        let task = Task.detached(priority: .utility) { () -> CatalogIconAsset? in
            let request = URLRequest(url: url, timeoutInterval: 20)
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            if let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) {
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 256,
                    kCGImageSourceShouldCacheImmediately: true
                ] as CFDictionary
                if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                    return CatalogIconAsset(thumbnail: image, original: nil)
                }
            }
            return CatalogIconAsset(thumbnail: nil, original: data)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result { cache.setObject(Entry(result), forKey: url as NSURL, cost: result.memoryCost) }
        return result
    }
}
