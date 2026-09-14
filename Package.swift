// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Ruri",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ruri", targets: ["Ruri"]),
        .executable(name: "ruri-cli", targets: ["RuriCLI"]),
        .executable(name: "ruri-monitor", targets: ["RuriMonitor"]),
        .library(name: "RuriCore", targets: ["RuriCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20"),
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0")
    ],
    targets: [
        .systemLibrary(name: "CZlib"),
        .target(name: "RuriLocalization", resources: [.process("Resources")]),
        .target(name: "RuriCore", dependencies: ["ZIPFoundation", "CZlib", "RuriLocalization", .product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "Ruri", dependencies: ["RuriCore", "RuriLocalization"], resources: [.copy("Resources/JavaBrands")]),
        .executableTarget(name: "RuriCLI", dependencies: ["RuriCore", "RuriLocalization"]),
        .executableTarget(name: "RuriMonitor", dependencies: ["RuriCore", "RuriLocalization"]),
        .testTarget(name: "RuriCoreTests", dependencies: ["RuriCore", "RuriLocalization"]),
        .testTarget(name: "RuriLocalizationTests", dependencies: ["RuriLocalization"])
    ]
)
