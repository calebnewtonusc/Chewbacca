// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Plynn",
    // macOS 15 is the real floor: every dependency supports 14 or lower, and the
    // 26-only pieces (Apple Intelligence polish, SpeechAnalyzer, Liquid Glass)
    // are all behind @available checks with working fallbacks.
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", from: "2.29.1"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "PlynnKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
            ]),
        .executableTarget(
            name: "Plynn",
            dependencies: [
                "PlynnKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]),
        .testTarget(
            name: "PlynnKitTests",
            dependencies: ["PlynnKit"],
            resources: [.copy("Fixtures")]),
    ]
)
