import SwiftUI
import RuriCore
import RuriLocalization

/// Instance labels retain exact loader versions and all imported components;
/// catalog compatibility summaries describe a different kind of metadata.
struct InstanceMetadata: View {
    private struct Component: Identifiable {
        let id: String
        let text: String
        let loader: String?
    }
    private let gameVersion: String
    private let components: [Component]
    private let summary: String
    private let compact: Bool

    init(instance: GameInstance, compact: Bool = false) {
        gameVersion = instance.gameVersion
        summary = instance.subtitle
        self.compact = compact
        if let declared = instance.repositoryComponents ?? instance.importedInstallation?.components {
            components = declared.isEmpty
                ? [.init(id: LoaderKind.vanilla.rawValue, text: Messages.CoreGameInstance.vanilla.localized, loader: LoaderKind.vanilla.modrinthLoader)]
                : declared.map { component in
                    let kind = LoaderKind.allCases.first { $0.title.caseInsensitiveCompare(component.name) == .orderedSame }
                    return Component(id: component.id, text: component.name + " " + component.version, loader: kind?.modrinthLoader)
                }
        } else {
            components = [.init(id: instance.loader.rawValue, text: instance.loaderLabel, loader: instance.loader.modrinthLoader)]
        }
    }

    /// Running rows describe the launch snapshot even if the saved instance
    /// has since been renamed or changed by another process.
    init(session: GameSession) {
        gameVersion = session.gameVersion
        compact = true
        let kind = LoaderKind(rawValue: session.loader)
        let text = (kind?.title ?? session.loader) + (session.loaderVersion.map { " " + $0 } ?? "")
        components = [.init(id: session.loader, text: text, loader: kind?.modrinthLoader)]
        summary = Messages.Discovery.minecraftVersion(session.gameVersion).localized + " · " + text
    }

    var body: some View {
        WrappingLayout(spacing: 6) {
            MetadataBadge(text: gameVersion, symbol: "cube", compact: compact)
            ForEach(components) { component in
                MetadataBadge(text: component.text, symbol: component.loader == nil ? "puzzlepiece.extension" : nil, loader: component.loader, compact: compact)
            }
        }
        .help(summary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }
}
