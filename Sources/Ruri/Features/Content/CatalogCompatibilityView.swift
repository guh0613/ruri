import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogGameVersionsBadge: View {
    let versions: [String]
    var body: some View {
        MetadataBadge(text: CatalogMetadata.versionSummary(versions), symbol: "cube")
            .help(D.supportedGameVersions(CatalogMetadata.sortedVersions(versions).joined(separator: ", ")).localized)
            .accessibilityLabel(D.supportedGameVersions(CatalogMetadata.sortedVersions(versions).joined(separator: ", ")).localized)
    }
}
struct CatalogLoaderBadges: View {
    let loaders: [String]
    var limit: Int? = nil
    private var unique: [String] { var seen = Set<String>(); return loaders.filter { seen.insert($0).inserted } }
    var body: some View {
        WrappingLayout(spacing: 6) {
            if unique.isEmpty { MetadataBadge(text: D.loadersUnknown.localized, symbol: "square.stack.3d.up") }
            ForEach(Array(unique.prefix(limit ?? unique.count)), id: \.self) { loader in
                MetadataBadge(text: CatalogMetadata.loaderTitle(loader), loader: loader)
            }
            if let limit, unique.count > limit { MetadataBadge(text: "+\(unique.count - limit)") }
        }
        .help(unique.map(CatalogMetadata.loaderTitle).joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(D.supportedLoaders(unique.map(CatalogMetadata.loaderTitle).joined(separator: ", ")).localized)
    }
}
