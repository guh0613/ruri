import SwiftUI
import RuriCore
import RuriLocalization

private typealias D = Messages.Discovery

struct CatalogGameVersionsBadge: View {
    private let text: String
    private let suffix: String?
    private let supportedVersions: String

    init(versions: [String]) {
        let summary = CatalogVersionBadgeCache.summary(versions)
        text = summary.text
        suffix = summary.additionalCount > 0 ? "+\(summary.additionalCount)" : nil
        supportedVersions = D.supportedGameVersions(summary.allVersions).localized
    }
    var body: some View {
        MetadataBadge(text: text, symbol: "cube", suffix: suffix)
            .help(supportedVersions)
            .accessibilityLabel(supportedVersions)
    }
}

/// Search hits can contain hundreds of game versions. Sorting those lists is
/// presentation preparation, not work to repeat during each layout pass.
@MainActor private enum CatalogVersionBadgeCache {
    struct Summary {
        let text: String
        let additionalCount: Int
        let allVersions: String
    }
    private static var summaries: [[String]: Summary] = [:]

    static func summary(_ versions: [String]) -> Summary {
        if let cached = summaries[versions] { return cached }
        let parts = CatalogMetadata.versionSummaryParts(versions)
        let result = Summary(text: parts.text, additionalCount: parts.additionalCount,
                             allVersions: CatalogMetadata.sortedVersions(versions).joined(separator: ", "))
        // The empty label is localized; resolve it in the current context.
        if !versions.isEmpty {
            if summaries.count >= 256 { summaries.removeAll(keepingCapacity: true) }
            summaries[versions] = result
        }
        return result
    }
}
struct CatalogLoaderBadges: View {
    let loaders: [String]
    var limit: Int? = nil
    var singleLine = false
    private var unique: [String] { var seen = Set<String>(); return loaders.filter { seen.insert($0).inserted } }
    var body: some View {
        Group {
            if singleLine { HStack(spacing: 6) { badges } }
            else { WrappingLayout(spacing: 6) { badges } }
        }
        .help(unique.map(CatalogMetadata.loaderTitle).joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(D.supportedLoaders(unique.map(CatalogMetadata.loaderTitle).joined(separator: ", ")).localized)
    }
    @ViewBuilder private var badges: some View {
        if unique.isEmpty { MetadataBadge(text: D.loadersUnknown.localized, symbol: "square.stack.3d.up") }
        ForEach(Array(unique.prefix(limit ?? unique.count)), id: \.self) { loader in
            MetadataBadge(text: CatalogMetadata.loaderTitle(loader), loader: loader)
        }
        if let limit, unique.count > limit { MetadataBadge(text: "+\(unique.count - limit)").fixedSize() }
    }
}

/// The same labeled facts appear in discovery cards and the project header.
struct CatalogProjectFacts: View {
    let project: CatalogProject
    var loaderLimit: Int? = nil
    var showUpdated = true

    var body: some View {
        WrappingLayout(spacing: 8) {
            CatalogGameVersionsBadge(versions: project.gameVersions)
            if !project.loaders.isEmpty { CatalogLoaderBadges(loaders: project.loaders, limit: loaderLimit) }
            MetadataBadge(text: LocalizedFormat.compactNumber(project.downloads), symbol: "arrow.down")
            if showUpdated, let updated = project.updated {
                MetadataBadge(text: LocalizedFormat.publishedDate(updated), symbol: "calendar")
            }
        }
    }
}

/// Compatibility stays scannable without giving every fact a separate container.
struct CatalogCompatibilityLine: View {
    let versions: [String]
    let loaders: [String]
    private var uniqueLoaders: [String] { Array(Set(loaders)).sorted() }
    private var fullDescription: String {
        [D.supportedGameVersions(CatalogMetadata.sortedVersions(versions).joined(separator: ", ")).localized,
         uniqueLoaders.isEmpty ? nil : D.supportedLoaders(uniqueLoaders.map(CatalogMetadata.loaderTitle).joined(separator: ", ")).localized]
            .compactMap { $0 }.joined(separator: " · ")
    }
    var body: some View {
        WrappingLayout(spacing: 10) {
            Label {
                let summary = CatalogMetadata.versionSummaryParts(versions)
                HStack(spacing: 6) {
                    Text(summary.text)
                    if summary.additionalCount > 0 { Text("+\(summary.additionalCount)").foregroundStyle(.tertiary) }
                }
            } icon: { Image(systemName: "cube") }
            if !uniqueLoaders.isEmpty {
                Label {
                    Text(uniqueLoaders.map(CatalogMetadata.loaderTitle).joined(separator: ", "))
                } icon: {
                    if uniqueLoaders.count == 1, let loader = uniqueLoaders.first {
                        LoaderGlyph.image(for: loader).resizable().scaledToFit().frame(width: 12, height: 12)
                    } else { Image(systemName: "square.stack.3d.up") }
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .help(fullDescription)
        .accessibilityElement(children: .ignore).accessibilityLabel(fullDescription)
    }
}
