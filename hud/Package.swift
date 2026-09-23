// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kyber",
    // Matches the floor Plynn settled on. Nothing here needs anything newer.
    platforms: [.macOS("14.0")],
    targets: [
        .target(name: "KyberKit"),
        .executableTarget(name: "Kyber", dependencies: ["KyberKit"]),
        // Doctor Strange skeleton overlay. A demo, not production.
        // Run: swift run HandDemo
        .executableTarget(name: "HandDemo"),
        // The portal on the HUD glass. Apple Vision feeds landmarks to a
        // transparent WKWebView that only draws. Run: swift run Portal
        .executableTarget(
            name: "Portal",
            dependencies: ["KyberKit"],
            resources: [.copy("Resources/portal")]
        ),
        // The agent's hands: acts through Accessibility and draws the agent
        // cursor where it acts. Run: swift run HudHand press --app X "Save"
        .executableTarget(name: "HudHand"),
        .testTarget(name: "KyberKitTests", dependencies: ["KyberKit"]),
    ]
)
