# Lowering a macOS App's Deployment Target

How to run a Swift app whose manifest claims it needs a newer macOS than you have. Most of the time the floor is set by two or three optional features, not by the app's actual work.

---

## The symptom

The app refuses to launch, or its tests die before a single one runs:

```
Library not loaded: /System/Library/Frameworks/FoundationModels.framework
  Referenced from: .../MyAppPackageTests
  (built for macOS 26.0 which is newer than running OS)
Reason: tried: ... (no such file, not in dyld cache)
```

That is dyld, not the compiler. The binary compiled fine against the newer SDK. It cannot load because a framework it hard-links does not exist on this OS.

## Check the dependencies before anything else

This one fact decides whether a port is worth attempting. If a dependency genuinely requires the newer OS, stop. If they are all lower, the app's floor is a choice its author made, not a constraint.

```bash
for p in .build/checkouts/*/; do
  echo "=== $(basename "$p") ==="
  grep -A6 "platforms:" "$p/Package.swift" 2>/dev/null | head -8
done
```

A package can only be as portable as the least portable thing it links.

## Find the real surface

Grep for the frameworks and symbols that landed in the version you cannot run. The list is usually short and lives in a handful of files.

```bash
grep -rln "FoundationModels\|SystemLanguageModel" Sources/
grep -rln "glassEffect\|GlassEffectContainer" Sources/
grep -rn "@available\|#available" Sources/   # existing gates, if any
```

If that last command returns nothing, the author never intended the code to run anywhere else. That is normal and it is not a problem, it just means you write the gates.

## Gate the types, not the call sites

Annotate the type once. The compiler then finds every call site for you by refusing to build them.

```swift
@available(macOS 26, *)
public actor AppleFMFormatter {
    // unchanged
}
```

A type marked this way cannot be a stored property of something that runs on older systems. Store it type-erased and reach it through helpers:

```swift
private let formatterBox: Any?

public init() {
    if #available(macOS 26, *) {
        formatterBox = AppleFMFormatter()
    } else {
        formatterBox = nil
    }
}

private var formatterReady: Bool {
    if #available(macOS 26, *), let f = formatterBox as? AppleFMFormatter {
        return f.ready
    }
    return false
}
```

Write one helper per operation rather than sprinkling `#available` through business logic. The call sites stay readable and the availability handling stays in one place.

## Protocol conformances need a stand-in

If the gated type conforms to a protocol that something else stores, you need a concrete value for the older path. A stub that throws is clearer than an optional everywhere:

```swift
public actor UnavailableEngine: TranscriptionEngine {
    public enum EngineError: Error { case requiresNewerOS }
    public nonisolated let displayName = "Unavailable (needs macOS 26)"
    public func start() async throws { throw EngineError.requiresNewerOS }
}
```

Then make sure selection logic can never pick it. Add an availability parameter with a default so existing call sites and tests keep compiling:

```swift
public static var appleEngineAvailable: Bool {
    if #available(macOS 26, *) { return true }
    return false
}

public static func select(
    preferred: Choice, ready: Bool,
    appleAvailable: Bool = Self.appleEngineAvailable
) -> Choice {
    guard appleAvailable else { return .fallback }
    // original logic
}
```

## SwiftUI needs wrappers, not inline branches

You cannot put `#available` in the middle of a view modifier chain. Extract a `ViewModifier` and a container view:

```swift
private struct CapsuleGlass: ViewModifier {
    let namespace: Namespace.ID
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("capsule", in: namespace)
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}
```

Apply it as `.modifier(CapsuleGlass(namespace: ns))`. Same trick for container types: wrap them in a small generic view that passes content straight through on older systems.

## Why lowering the target is what actually fixes dyld

Set the floor in both places. They serve different masters:

```swift
platforms: [.macOS("15.0")],   // Package.swift, drives the linker
```

```xml
<key>LSMinimumSystemVersion</key>
<string>15.0</string>          <!-- Info.plist, drives Launch Services -->
```

When the deployment target is below a framework's availability, Swift weak-links it. Missing symbols resolve to null instead of aborting the load, and your `#available` checks keep you from touching them. Verify rather than assume:

```bash
otool -L path/to/binary | grep -i FrameworkName     # want: "weak"
otool -l path/to/binary | grep -A4 LC_BUILD_VERSION # want: minos 15.0, sdk 26.0
```

`minos` below `sdk` is the whole point. You are compiling with the new SDK and running on the old OS.

## Let the compiler enumerate the rest

After lowering the target, build. Every ungated use of a too-new API is now a hard error with a file and line. That list is more reliable than any grep you write by hand.

## Two things to fix before you call it done

**Tests that assert OS-dependent defaults.** A selection function with an availability-derived default parameter returns different values on different machines. Pass the value explicitly so the test measures logic, not the host:

```swift
XCTAssertEqual(select(preferred: .auto, ready: false, appleAvailable: true), .apple)
```

Then add a second test for the unavailable path. The gated behavior deserves coverage too.

**Auto-updaters.** If the app uses Sparkle and upstream ships builds for the newer OS, a background check will happily replace your working install with one that cannot launch. Turn automatic checks off on the port:

```xml
<key>SUEnableAutomaticChecks</key>
<false/>
```

## Signing for local use

Build scripts usually hardcode the maintainer's Developer ID. Override it:

```bash
IDENTITY="-" ./scripts/make-app.sh          # ad-hoc
```

Prefer your own Apple Development certificate over ad-hoc when the app requests accessibility or microphone access. macOS keys those grants to the code signature, and an ad-hoc signature is identified by its hash, so every rebuild looks like a different app and you re-grant permissions each time. A real certificate keys on team and bundle ID, which survive rebuilds.

```bash
security find-identity -v -p codesigning
IDENTITY="Apple Development: YOUR NAME (TEAMID)" ./scripts/make-app.sh --install
```

## Verify it actually runs

A successful build proves nothing about loading. Launch it and confirm the process survives:

```bash
open /Applications/App.app
for i in 1 2 3 4; do echo "$(pgrep -f '/Applications/App.app' | tr '\n' ' ')"; sleep 6; done
find ~/Library/Logs/DiagnosticReports -name "App*" -newermt "-10 minutes"
```

A stable PID across several checks and no crash report is the result you want. A PID that changes is a restart loop, which looks like success in a single check.

## What you give up

Be honest in the writeup about what the fallbacks cost. Porting past an OS floor means running the author's second-choice path for whatever the newer APIs provided. If the fallback is materially worse for your use, upgrading the OS is the better answer.
