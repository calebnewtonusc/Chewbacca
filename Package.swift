// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BobHUD",
    // Matches the floor Plynn settled on. Nothing here needs anything newer.
    platforms: [.macOS("14.0")],
    targets: [
        .target(name: "BobHUDKit"),
        .executableTarget(name: "BobHUD", dependencies: ["BobHUDKit"]),
        .testTarget(name: "BobHUDKitTests", dependencies: ["BobHUDKit"]),
    ]
)
