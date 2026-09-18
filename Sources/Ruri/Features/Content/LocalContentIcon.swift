import SwiftUI
import AppKit
import ImageIO
import RuriCore

struct LocalContentIcon: View {
    let file: LocalContentFile
    var size: CGFloat = 32
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else {
                Image(systemName: file.kind == .mod ? "puzzlepiece.extension.fill" : file.kind == .shader ? "sun.max.fill" : "square.stack.3d.up.fill")
                    .font(.system(size: size * 0.55)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary.opacity(0.35))
            }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.18))
            .accessibilityHidden(true)
            .task(id: file.presentationRevision) {
                image = nil
                guard let path = file.metadata?.iconPath else { return }
                let asset = await LocalContentIconStore.shared.image(at: file.url, path: path, revision: file.presentationRevision)
                guard !Task.isCancelled, let thumbnail = asset?.thumbnail else { return }
                image = NSImage(cgImage: thumbnail, size: .zero)
            }
    }
}

private actor LocalContentIconStore {
    static let shared = LocalContentIconStore()
    private final class Entry: NSObject {
        let asset: CatalogIconAsset
        init(_ asset: CatalogIconAsset) { self.asset = asset }
    }
    private let cache = NSCache<NSString, Entry>()
    private init() { cache.totalCostLimit = 16 * 1024 * 1024; cache.countLimit = 256 }
    func image(at url: URL, path: String, revision: String) -> CatalogIconAsset? {
        guard !Task.isCancelled else { return nil }
        let key = revision as NSString
        if let entry = cache.object(forKey: key) { return entry.asset }
        guard let data = LocalModMetadata.iconData(at: url, path: path),
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let asset = CatalogIconAsset(thumbnail: image, original: nil)
        cache.setObject(Entry(asset), forKey: key, cost: asset.memoryCost)
        return asset
    }
}
