import Foundation
import RuriLocalization

extension GameInstaller {
    func installLoaders(_ input: GameInstance, base: VersionManifest, concurrency: Int,
                        progress: @Sendable @escaping (InstallProgress) async -> Void) async throws -> (instance: GameInstance, manifest: VersionManifest) {
        var selections = input.loaderSelections
        if let issue = LoaderCompatibility.combinationIssue(selections.map(\.loader), game: input.gameVersion) { throw RuriError.message(issue) }
        for index in selections.indices where selections[index].version.isEmpty {
            guard let version = try await loaderVersions(selections[index].loader, game: input.gameVersion).first else {
                throw RuriError.message(Messages.CoreInstaller.loaderVersionUnavailable(selections[index].loader.title))
            }
            selections[index].version = version
        }
        try LoaderCompatibility.validate(selections, game: input.gameVersion)
        var manifest = base
        for index in selections.indices {
            let selection = selections[index]
            var component = input
            component.loader = selection.loader; component.loaderVersion = selection.version
            await progress(InstallProgress(Messages.CoreInstaller.installingInstance(selection.loader.title)))
            let child: VersionManifest
            switch selection.loader {
            case .forge, .neoforge:
                child = try await ForgeInstaller(paths: paths, downloader: downloader, protectExistingFiles: protectExistingFiles)
                    .install(instance: component, base: manifest, concurrency: concurrency, progress: progress)
            case .optifine:
                component.loaderVersion = OptiFineCatalog.normalized(selection.version, game: input.gameVersion)
                child = try await OptiFineInstaller(paths: paths, downloader: downloader, protectExistingFiles: protectExistingFiles)
                    .install(instance: component, base: manifest, companions: selections.filter { $0.loader != .optifine }, progress: progress)
                selections[index].version = component.loaderVersion!
            case .liteloader:
                let result = try await LiteLoaderCatalog.profile(game: input.gameVersion, version: selection.version, base: manifest)
                child = result.0; selections[index].version = result.1
            default:
                let url = try LoaderEndpoints.profile(loader: selection.loader, game: input.gameVersion, version: selection.version)
                child = try await HTTPClient.shared.get(VersionManifest.self, from: url)
            }
            manifest = manifest.merging(child: child)
        }
        if selections.count > 1 { manifest = try LoaderLaunchArguments.combining(manifest, loaders: selections.map(\.loader)) }
        var instance = input; instance.setLoaderSelections(selections)
        return (instance, manifest)
    }
}

enum LoaderLaunchArguments {
    /// LaunchWrapper needs LiteLoader and OptiFine registered before FML injects
    /// its cascading tweakers. Preserve every unrelated argument and its order.
    static func combining(_ manifest: VersionManifest, loaders: [LoaderKind]) throws -> VersionManifest {
        if Set(loaders) == [.forge, .optifine], OptiFineForgeSupport.launchKind(manifest) != nil,
           manifest.mainClass != "net.minecraft.launchwrapper.Launch" { return manifest }
        guard manifest.mainClass == "net.minecraft.launchwrapper.Launch" else {
            throw RuriError.message(Messages.LoaderSelection.unsupportedLaunchMethod)
        }
        let lite = "com.mumfrey.liteloader.launch.LiteLoaderTweaker"
        let optifine = "optifine.OptiFineForgeTweaker"
        let forge = ["cpw.mods.fml.common.launcher.FMLTweaker", "net.minecraftforge.fml.common.launcher.FMLTweaker"]
        let known = Set([lite, optifine, "optifine.OptiFineTweaker"] + forge)
        func reorder(_ arguments: [String]) -> [String] {
            var kept: [String] = [], found = Set<String>(), index = 0
            while index < arguments.count {
                if arguments[index] == "--tweakClass", index + 1 < arguments.count, known.contains(arguments[index + 1]) {
                    found.insert(arguments[index + 1]); index += 2
                } else { kept.append(arguments[index]); index += 1 }
            }
            let tweakers = (loaders.contains(.liteloader) ? [lite] : [])
                + (loaders.contains(.optifine) ? [optifine] : []) + forge.filter { found.contains($0) }
            return kept + tweakers.flatMap { ["--tweakClass", $0] }
        }
        var result = manifest
        if let legacy = manifest.minecraftArguments { result.minecraftArguments = try ArgumentTokenizer.join(reorder(ArgumentTokenizer.split(legacy))) }
        else if let arguments = manifest.arguments?.game {
            // Component tweakers are unconditional. Keep conditional game flags.
            let texts = arguments.compactMap { if case .text(let value) = $0 { value } else { nil } }
            let conditional = arguments.filter { if case .conditional = $0 { true } else { false } }
            result.arguments?.game = conditional + reorder(texts).map(LaunchArgument.text)
        }
        return result
    }
}
