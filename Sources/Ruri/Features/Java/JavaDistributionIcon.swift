import AppKit
import SwiftUI
import RuriCore

/// Verified distributor artwork, fitted to one optical size. Version numbers
/// stay in the runtime title; the mark identifies its distribution or source.
struct JavaDistributionIcon: View {
    let runtime: JavaRuntime?
    let path: String

    var body: some View {
        let distribution = JavaDistribution(vendor: runtime?.vendor ?? "", path: path)
        Group {
            if let image = JavaBrandImages.image(for: distribution) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "cup.and.saucer.fill").resizable().scaledToFit().foregroundStyle(Theme.accent)
            }
        }
        .frame(width: distribution.artworkSize.width, height: distribution.artworkSize.height)
        .frame(width: 44, height: 44)
        // The original marks retain their colors and remain legible in Dark Mode.
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .help(distribution.name)
        .accessibilityHidden(true)
    }
}

enum JavaDistribution: String {
    case homebrew, zulu, azul, graalvm, microsoft, generic

    init(vendor: String, path: String) {
        let vendor = vendor.lowercased()
        let path = path.lowercased()
        let components = URL(fileURLWithPath: path).pathComponents
        // A macOS bundle can end in .jdk or simply graalvm-jdk-<version>.
        // For an unpacked JDK, the distribution directory directly contains bin.
        let installation: String
        if let contents = components.lastIndex(of: "contents"), contents > 0 {
            installation = components[contents - 1]
        } else {
            installation = components.dropLast(2).last ?? ""
        }
        func named(_ prefix: String) -> Bool {
            installation == prefix || ["-", ".", "@"].contains { installation.hasPrefix(prefix + $0) }
        }
        if vendor.contains("graalvm") || named("graalvm") { self = .graalvm }
        else if vendor.contains("zulu") || named("zulu") { self = .zulu }
        else if vendor.contains("azul") { self = .azul }
        else if vendor.contains("microsoft") || named("microsoft") { self = .microsoft }
        else if vendor.contains("homebrew") || path.contains("/cellar/openjdk") { self = .homebrew }
        else { self = .generic }
    }

    var name: String {
        switch self {
        case .homebrew: "Homebrew"
        case .zulu: "Zulu"
        case .azul: "Azul"
        case .graalvm: "GraalVM"
        case .microsoft: "Microsoft"
        case .generic: "Java"
        }
    }

    var artworkSize: CGSize {
        switch self {
        case .homebrew: CGSize(width: 30, height: 36)
        case .graalvm: CGSize(width: 38, height: 36)
        case .zulu: CGSize(width: 32, height: 34)
        case .azul: CGSize(width: 34, height: 24)
        case .microsoft, .generic: CGSize(width: 26, height: 26)
        }
    }
}

@MainActor private enum JavaBrandImages {
    private static var images: [JavaDistribution: NSImage] = [:]
    // Locate the installed resource bundle first so a packaged app never
    // depends on SwiftPM's absolute build-directory fallback.
    private static let resources: Bundle? = {
        let roots = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        return roots.lazy.compactMap { Bundle(url: $0.appendingPathComponent("Ruri_Ruri.bundle")) }.first
    }()

    static func image(for distribution: JavaDistribution) -> NSImage? {
        guard distribution != .generic else { return nil }
        if let image = images[distribution] { return image }
        guard let url = resources?.url(forResource: distribution.rawValue, withExtension: "svg", subdirectory: "JavaBrands"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[distribution] = image
        return image
    }
}
