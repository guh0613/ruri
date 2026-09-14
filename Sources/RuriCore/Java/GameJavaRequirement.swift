import Foundation
import RuriLocalization

/// The manifest specifies a minimum; a user's major selection and a pack's
/// supported versions are additional constraints, not download instructions.
public struct GameJavaRequirement: Sendable {
    public let minimumMajor: Int
    public let recommendedMajor: Int
    public let architecture: String
    public let preferredPath: String?
    private let selectedMajor: Int?
    private let supportedMajors: [Int]?
    private let requiresLegacyJava: Bool

    public init(instance: GameInstance, manifest: VersionManifest) throws {
        minimumMajor = manifest.requiredJava
        recommendedMajor = try instance.preferredJavaMajor(default: minimumMajor)
        architecture = GameInstaller.architecture(for: manifest)
        preferredPath = instance.javaPath
        selectedMajor = instance.javaMajor
        supportedMajors = instance.supportedJavaMajors
        // Old LaunchWrapper casts the system class loader to URLClassLoader,
        // which is no longer valid on Java 9 and later.
        requiresLegacyJava = minimumMajor <= 8 && manifest.mainClass == "net.minecraft.launchwrapper.Launch" && manifest.libraries.contains {
            $0.name.hasPrefix("net.minecraft:launchwrapper:") &&
                String($0.name.split(separator: ":").last ?? "").compare("1.13", options: .numeric) == .orderedAscending
        }
    }

    public func accepts(major: Int, architecture: String) -> Bool {
        major >= minimumMajor && architecture == self.architecture &&
            (selectedMajor == nil || selectedMajor == major) &&
            (supportedMajors?.isEmpty != false || supportedMajors!.contains(major)) &&
            (!requiresLegacyJava || major <= 8)
    }

    public func validate(_ runtime: JavaRuntime) throws {
        guard accepts(major: runtime.major, architecture: runtime.architecture) else {
            throw RuriError.message(Messages.CoreLaunch.javaVersionIncompatible)
        }
    }

    /// Nil means there is no compatible local runtime. Invalid explicit paths
    /// remain errors so that downloading Java cannot silently override settings.
    public func select(from runtimes: [JavaRuntime]) throws -> JavaRuntime? {
        if let preferredPath {
            guard let runtime = runtimes.first(where: { JavaDiscovery.sameExecutable($0.path, preferredPath) }) else {
                throw RuriError.message(Messages.CoreJavaRuntime.selectedJavaUnavailable)
            }
            try validate(runtime)
            return runtime
        }
        return runtimes.filter { accepts(major: $0.major, architecture: $0.architecture) }.sorted {
            if ($0.major == recommendedMajor) != ($1.major == recommendedMajor) { return $0.major == recommendedMajor }
            if $0.major != $1.major { return $0.major < $1.major }
            let order = $0.version.compare($1.version, options: .numeric)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedDescending
        }.first
    }

    public func require(from runtimes: [JavaRuntime]) throws -> JavaRuntime {
        guard let runtime = try select(from: runtimes) else {
            throw RuriError.message(Messages.CoreGameJavaRequirement.missingCompatibleJava(String(recommendedMajor), architecture))
        }
        return runtime
    }
}

extension JavaDiscovery {
    /// Installation processors are ordinary Java tools. Their CPU architecture
    /// need not match the game's native libraries, and newer Java can run them.
    static func selectForInstallation(from runtimes: [JavaRuntime], minimumMajor: Int) -> JavaRuntime? {
        runtimes.filter { $0.major >= minimumMajor && ($0.isNative || $0.architecture == "x86_64") }.sorted {
            if $0.isNative != $1.isNative { return $0.isNative }
            if $0.major != $1.major { return $0.major < $1.major }
            return $0.version.compare($1.version, options: .numeric) == .orderedDescending
        }.first
    }
}
