// swift-tools-version: 6.0
import PackageDescription

// Its own package rather than a target of hud/, because FluidAudio brings
// binary targets and a minute of first build that the display's own
// `swift test` loop should not carry.
let package = Package(
    name: "hud-voice",
    platforms: [.macOS("14.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.8")
    ],
    targets: [
        .target(name: "HudVoiceKit"),
        .executableTarget(
            name: "hud-voice",
            dependencies: [
                "HudVoiceKit",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .testTarget(name: "HudVoiceKitTests", dependencies: ["HudVoiceKit"]),
    ]
)
