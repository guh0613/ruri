// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ruri",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ruri", targets: ["Ruri"]),
        .executable(name: "ruri-cli", targets: ["RuriCLI"]),
        .library(name: "RuriCore", targets: ["RuriCore"])
    ],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .systemLibrary(name: "CZlib"),
        .target(name: "RuriCore", dependencies: ["ZIPFoundation", "CZlib"]),
        .executableTarget(name: "Ruri", dependencies: ["RuriCore"]),
        .executableTarget(name: "RuriCLI", dependencies: ["RuriCore"]),
        .testTarget(name: "RuriCoreTests", dependencies: ["RuriCore"])
    ]
)
