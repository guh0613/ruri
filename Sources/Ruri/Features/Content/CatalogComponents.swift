import AppKit
import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogProjectCard: View {
    let project: CatalogProject
    var compact = false
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                CatalogIcon(url: project.icon, size: compact ? 52 : 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title).font(.headline).lineLimit(1)
                    Text(Messages.AppDiscoverView.authorBy(project.author).localized).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if compact { Text(project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
                if compact { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
            if !compact {
                Text(project.summary).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                    .frame(height: 51, alignment: .topLeading).multilineTextAlignment(.leading)
            }
            VStack(alignment: .leading, spacing: 7) {
                CatalogGameVersionsBadge(versions: project.gameVersions)
                if ["mod", "modpack", "shader"].contains(project.type) {
                    CatalogLoaderBadges(loaders: project.loaders, limit: 3)
                }
            }
            HStack(spacing: 8) {
                Label(LocalizedFormat.compactNumber(project.downloads), systemImage: "arrow.down").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let category = project.categories.first { Text(CatalogCategoryPresentation.title(category)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if !compact { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.035) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.primary.opacity(hovering ? 0.13 : 0.065)))
        .contentShape(RoundedRectangle(cornerRadius: 14)).onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
struct CatalogIcon: View {
    let url: URL?
    var size: CGFloat = 64
    @State private var image: NSImage?
    @MainActor private static let cache = NSCache<NSURL, NSImage>()
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "shippingbox.fill").resizable().scaledToFit().padding(size * 0.23).foregroundStyle(Theme.accent).background(Theme.accent.opacity(0.08)) }
        }.frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23)).accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url else { return }
            if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  !Task.isCancelled, let loaded = NSImage(data: data) else { return }
            Self.cache.totalCostLimit = 24 * 1024 * 1024
            Self.cache.setObject(loaded, forKey: url as NSURL, cost: data.count)
            image = loaded
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
