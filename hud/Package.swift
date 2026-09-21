// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BobHUD",
    // Matches the floor Plynn settled on. Nothing here needs anything newer.
    platforms: [.macOS("14.0")],
    targets: [
        .target(name: "BobHUDKit"),
        .executableTarget(name: "BobHUD", dependencies: ["BobHUDKit"]),
        // Doctor Strange skeleton overlay. A demo, not production.
        // Run: swift run HandDemo
        .executableTarget(name: "HandDemo"),
        // The portal on the HUD glass. Apple Vision feeds landmarks to a
        // transparent WKWebView that only draws. Run: swift run Portal
        .executableTarget(
            name: "Portal",
            dependencies: ["BobHUDKit"],
            resources: [.copy("Resources/portal")]
        ),
        .testTarget(name: "BobHUDKitTests", dependencies: ["BobHUDKit"]),
    ]
)
