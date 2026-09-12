// swift-tools-version: 6.0
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
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .systemLibrary(name: "CZlib"),
        .target(name: "RuriLocalization", resources: [.process("Resources")]),
        .target(name: "RuriCore", dependencies: ["ZIPFoundation", "CZlib", "RuriLocalization"]),
        .executableTarget(name: "Ruri", dependencies: ["RuriCore", "RuriLocalization"]),
        .executableTarget(name: "RuriCLI", dependencies: ["RuriCore", "RuriLocalization"]),
        .executableTarget(name: "RuriMonitor", dependencies: ["RuriCore", "RuriLocalization"]),
        .testTarget(name: "RuriCoreTests", dependencies: ["RuriCore", "RuriLocalization"]),
        .testTarget(name: "RuriLocalizationTests", dependencies: ["RuriLocalization"])
    ]
)
