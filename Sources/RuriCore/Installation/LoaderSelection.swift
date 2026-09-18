import Foundation
import RuriLocalization

public struct LoaderSelection: Codable, Hashable, Sendable, Identifiable {
    public let loader: LoaderKind
    public var version: String
    public var id: LoaderKind { loader }
    public init(loader: LoaderKind, version: String) { self.loader = loader; self.version = version }

    public static func ordered(_ selections: [Self]) -> [Self] {
        let order: [LoaderKind] = [.forge, .neoforge, .fabric, .quilt, .legacyfabric, .liteloader, .optifine]
        return selections.sorted { (order.firstIndex(of: $0.loader) ?? -1) < (order.firstIndex(of: $1.loader) ?? -1) }
    }
}

public enum LoaderCompatibility {
    public static func combinationIssue(_ loaders: [LoaderKind], game: String) -> String? {
        guard !loaders.contains(.vanilla), Set(loaders).count == loaders.count else {
            return Messages.LoaderSelection.invalidSelection.localized
        }
        guard loaders.count > 1 else { return nil }
        // Loader families have pairwise exclusions independent of game age.
        // LiteLoader and OptiFine conflict even when Forge is also selected.
        let selected = Set(loaders)
        guard selected == [.forge, .optifine] || selected == [.forge, .liteloader] else {
            return Messages.LoaderSelection.incompatibleLoaders.localized
        }
        return nil
    }

    public static func warnings(_ selections: [LoaderSelection], game: String) -> [String] {
        guard let forge = selections.first(where: { $0.loader == .forge })?.version else { return [] }
        let version = forge.hasPrefix(game + "-") ? String(forge.dropFirst(game.count + 1)) : forge
        let kinds = Set(selections.map(\.loader))
        // Known problems in specific builds remain visible as advisories.
        if game == "1.12.2", kinds.contains(.liteloader),
           MinecraftDependencyVersion.compare(version, "14.23.5.2760") != .orderedAscending,
           MinecraftDependencyVersion.compare(version, "14.23.5.2773") == .orderedAscending {
            return [Messages.LoaderSelection.forgeLiteLoaderWarning.localized]
        }
        if game == "1.14.4", kinds.contains(.optifine), MinecraftDependencyVersion.compare(version, "28.2.2") != .orderedAscending {
            return [Messages.LoaderSelection.forgeOptiFineWarning.localized]
        }
        return []
    }

    public static func validate(_ selections: [LoaderSelection], game: String) throws {
        if let issue = combinationIssue(selections.map(\.loader), game: game) { throw RuriError.message(issue) }
        guard selections.allSatisfy({ !$0.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw RuriError.message(Messages.CoreInstanceComponents.loaderVersionSelectionRequired)
        }
    }
}

extension GameInstance {
    public var loaderSelections: [LoaderSelection] {
        if let components = repositoryComponents ?? importedInstallation?.components {
            return LoaderSelection.ordered(components.compactMap { component in
                guard let loader = LoaderKind.allCases.first(where: { $0 != .vanilla && $0.title == component.name }) else { return nil }
                return LoaderSelection(loader: loader, version: component.version)
            })
        }
        return loader == .vanilla ? [] : [.init(loader: loader, version: loaderVersion ?? "")]
    }

    public var loaderSummary: String {
        let selections = loaderSelections
        return selections.isEmpty ? LoaderKind.vanilla.title : selections.map { $0.loader.title + " " + $0.version }.joined(separator: " + ")
    }

    public mutating func setLoaderSelections(_ selections: [LoaderSelection]) {
        let selections = LoaderSelection.ordered(selections)
        loader = selections.first?.loader ?? .vanilla
        loaderVersion = selections.first?.version
        repositoryComponents = selections.map { .init(name: $0.loader.title, version: $0.version) }
    }
}
