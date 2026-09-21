import AppKit
import ApplicationServices

/// Puts a window behind the portal.
///
/// The portal is transparent glass with a hole burnt in it, so there is no
/// screen capture anywhere in this path and nothing is being composited. The
/// app's real window is simply moved to sit behind the hole, and you see it
/// because the glass above it has been erased. Live, at zero latency, and
/// interactive if the portal ever stops being click-through.
///
/// WHY ACCESSIBILITY AND NOT SCREENCAPTUREKIT. Capturing the window and
/// drawing it inside the ring is the obvious build and it is worse in every
/// way that matters here: a frame of latency, a second encode of pixels that
/// are already on screen, a recording indicator in the menu bar, and a
/// picture of a window rather than the window. Moving the real thing costs
/// one Accessibility grant and nothing per frame.
///
/// WHY THE WINDOW IS INSCRIBED, NOT FITTED. A rectangle that covers the
/// circle spills out past the rim; one inscribed inside it never does. For a
/// square window the side is r*sqrt(2), and anything wider than tall gets
/// the same treatment on its own aspect, so the corners stay inside the
/// burnt edge no matter what shape the window is.
@MainActor
enum WindowPlacer {
    /// Bring `appName` forward and move its front window behind the circle.
    ///
    /// Returns false when Accessibility has not been granted, because that is
    /// the one failure a caller has to report rather than retry.
    /// Ask for Accessibility, with the system prompt that has a button
    /// straight to the right pane.
    ///
    /// Never hand somebody a path through System Settings when the API will
    /// put the sheet in front of them. Called once, when a portal is first
    /// armed, so an unarmed portal never asks for anything it does not need.
    static func requestTrustIfNeeded() -> Bool {
        if AXIsProcessTrusted() { return true }
        // The literal key, not `kAXTrustedCheckOptionPrompt`. That symbol is
        // a global `var` in the C header, so Swift 6 refuses it as shared
        // mutable state. The string it holds is API and has not changed.
        let options = ["AXTrustedCheckOptionPrompt": true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @discardableResult
    static func place(appName: String, centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let app = runningApp(named: appName) else { return false }

        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first
        else { return false }

        // Keep the window's own aspect so a wide Notes window does not become
        // a square, then shrink it until its diagonal fits the circle.
        var sizeRef: CFTypeRef?
        var current = CGSize(width: radius * 1.4, height: radius * 1.4)
        if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let value = sizeRef, CFGetTypeID(value) == AXValueGetTypeID() {
            var s = CGSize.zero
            if AXValueGetValue(value as! AXValue, .cgSize, &s), s.width > 1, s.height > 1 {
                current = s
            }
        }
        let diagonal = (current.width * current.width + current.height * current.height).squareRoot()
        let scale = (radius * 2) / max(diagonal, 1)
        var size = CGSize(width: current.width * scale, height: current.height * scale)
        // A window shrunk below its own minimum silently keeps its old size,
        // and then the corners hang outside the rim. A floor here at least
        // makes that visible rather than mysterious.
        size.width = max(size.width, 120)
        size.height = max(size.height, 80)

        // Accessibility uses top-left origin on the main display, which is the
        // same convention the web layer reports in, so the point passes
        // straight through with no flip.
        var origin = CGPoint(x: centerX - size.width / 2, y: centerY - size.height / 2)

        guard let posValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        app.activate()
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        return true
    }

    /// Launch the app if it is not already up, and wait briefly for a window.
    ///
    /// `nonisolated` and blocking, so it is called from a background queue.
    /// It waits up to seven seconds for a cold app to come up, and holding
    /// the main actor for that long would freeze the portal's own rendering
    /// at exactly the moment somebody is drawing a circle.
    nonisolated static func ensureRunning(appName: String) -> NSRunningApplication? {
        if let app = runningApp(named: appName) { return app }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appName)
            ?? appURL(named: appName)
        else { return nil }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let sem = DispatchSemaphore(value: 0)
        var launched: NSRunningApplication?
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            launched = app
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 6)
        // A launched app has no window for a moment, and placing into nothing
        // fails silently, so give it a beat rather than racing it.
        if launched != nil { Thread.sleep(forTimeInterval: 0.8) }
        return launched ?? runningApp(named: appName)
    }

    nonisolated private static func runningApp(named name: String) -> NSRunningApplication? {
        let lower = name.lowercased()
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && (($0.localizedName?.lowercased() == lower)
                    || ($0.bundleIdentifier?.lowercased() == lower))
        }
    }

    nonisolated private static func appURL(named name: String) -> URL? {
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities"] {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
