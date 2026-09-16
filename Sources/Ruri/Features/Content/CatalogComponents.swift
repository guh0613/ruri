import AppKit
import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogProjectCard: View {
    let project: CatalogProject
    var compact = false
    var body: some View {
        Group {
            if compact {
                HStack(spacing: 14) {
                    CatalogIcon(url: project.icon, size: 48)
                    VStack(alignment: .leading, spacing: 5) {
                        title
                        Text(project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                        compatibility
                        footer(showsChevron: false)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 18).padding(.vertical, 15)
            } else {
                Surface(padding: 20, shadow: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            CatalogIcon(url: project.icon, size: 48)
                            title.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 56, alignment: .top)
                        Text(project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                            .frame(height: 36, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 8) {
                            compatibility
                            MetadataBadge(text: LocalizedFormat.compactNumber(project.downloads), symbol: "arrow.down")
                        }
                        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: .infinity, alignment: .topLeading)
                        footer(showsChevron: true).frame(height: 16)
                    }.frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 214)
                }

            }
        }
        .multilineTextAlignment(.leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title).font(.headline).lineLimit(compact ? 1 : 2).help(project.title)
            Text(Messages.AppDiscoverView.authorBy(project.author).localized).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
    private var compatibility: some View {
        var seen = Set<String>()
        let loaders = project.loaders.filter { seen.insert($0).inserted }
        return WrappingLayout(spacing: 8) {
            CatalogGameVersionsBadge(versions: project.gameVersions)
            ForEach(Array(loaders.prefix(3)), id: \.self) { loader in
                MetadataBadge(text: CatalogMetadata.loaderTitle(loader), loader: loader)
            }
            if loaders.count > 3 { MetadataBadge(text: "+\(loaders.count - 3)") }
        }
        .help(project.loaders.map(CatalogMetadata.loaderTitle).joined(separator: ", "))
    }
    private func footer(showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            if let category = project.categories.first {
                Label(CatalogCategoryPresentation.title(category), systemImage: "tag")
                    .lineLimit(1).help(CatalogCategoryPresentation.title(category))
            }
            if compact {
                Label(LocalizedFormat.compactNumber(project.downloads), systemImage: "arrow.down").fixedSize()
            }
            if let updated = project.updated {
                Label(LocalizedFormat.publishedDate(updated), systemImage: "calendar").fixedSize()
            }
            Spacer(minLength: 0)
            if showsChevron { Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).accessibilityHidden(true) }
        }.font(.caption).foregroundStyle(.secondary)
    }

}

struct CatalogIcon: View {
    let url: URL?
    var size: CGFloat = 64
    @State private var image: NSImage?
    @State private var loadedURL: URL?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(size * 0.23).foregroundStyle(Theme.accent).background(Theme.accent.opacity(0.08)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23)).accessibilityHidden(true)
        .task(id: url) {
            guard loadedURL != url || image == nil else { return }
            if loadedURL != url { image = nil }
            guard let url else { loadedURL = nil; return }
            let asset = await CatalogIconStore.shared.image(at: url)
            guard !Task.isCancelled, let asset else { return }
            if let thumbnail = asset.thumbnail {
                image = NSImage(cgImage: thumbnail, size: .zero)
            } else if let original = asset.original {
                // Keep support for vector formats not handled by ImageIO.
                image = NSImage(data: original)
            }
            if image != nil { loadedURL = url }
        }
    }
}
struct CatalogErrorBanner: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer(minLength: 8)
            Button(Messages.AppDiscoverView.retry.localized, action: retry)
        }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
enum CatalogCategoryPresentation {
    static func title(_ name: String) -> String {
        switch name.lowercased() {
        case "adventure": D.categoryAdventure.localized
        case "technology": D.categoryTechnology.localized
        case "magic": D.categoryMagic.localized
        case "optimization", "performance": D.categoryOptimization.localized
        case "decoration": D.categoryDecoration.localized
        case "utility": D.categoryUtility.localized
        case "worldgen": D.categoryWorldgen.localized
        case "library": D.categoryLibrary.localized
        case "storage": D.categoryStorage.localized
        case "equipment": D.categoryEquipment.localized
        case "quests": D.categoryQuests.localized
        case "kitchen-sink": D.categoryKitchenSink.localized
        default: name.replacingOccurrences(of: "-", with: " ").localizedCapitalized
        }
    }
}
