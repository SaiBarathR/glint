// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GlintCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GlintCore", targets: ["GlintCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(name: "GlintCore", dependencies: ["Yams"]),
        .testTarget(name: "GlintCoreTests", dependencies: ["GlintCore"]),
    ]
)
