import AppKit
import BobHUDKit
import WebKit

/// The Doctor Strange portal on the HUD glass.
///
/// Pinch, draw a circle in the air, a portal burns itself open over whatever
/// you were doing. Pinch again to collapse it.
///
/// ARCHITECTURE, AND WHY IT IS NOT THE OBVIOUS ONE. The quick way to get this
/// on the HUD is to point a WKWebView at the browser build and let MediaPipe
/// open the camera. That works and it is the wrong build: a second camera
/// stream next to the one this process already runs, a WASM model pulled off
/// a CDN at every launch, and several times the CPU of what is already here.
///
/// So the split is:
///
///   Apple Vision  ->  LandmarkBridge  ->  WKWebView  ->  canvas
///   (7.56ms/frame)    (y flip, order)     (no camera)    (draws)
///
/// The gesture logic lives in the web layer rather than in Swift, which
/// looks backwards until you count implementations: the circle detector, the
/// least-squares fit, the mirror mapping and the open/close state machine
/// have 53 tests in OpenVision. Rewriting them in Swift would mean two
/// implementations of subtle geometry and tests for one of them.
///
/// The window is the same trick as OverlayWindow: one borderless transparent
/// panel over the whole screen that ignores the mouse completely, so the
/// portal is glass you cannot touch and everything underneath keeps working.
@MainActor
final class PortalController: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var panel: NSPanel?
    private var web: WKWebView?
    private let tracker = HandTracker()
    private var ready = false
    /// Frames dropped because the page had not finished loading. Reported on
    /// quit, because "it did nothing" and "it did nothing for the first two
    /// seconds" are different bugs.
    private var droppedBeforeReady = 0

    func applicationDidFinishLaunching(_: Notification) {
        // Bundle.main first, because that is where bundle-portal.sh puts the
        // web layer: Contents/Resources/portal. SwiftPM's own resource bundle
        // is the fallback for `swift run`, which is useful for a quick check
        // but cannot get camera access, so it is the secondary path and not
        // the primary one.
        guard let html =
            Bundle.main.url(forResource: "portal", withExtension: "html", subdirectory: "portal")
            ?? Bundle.module.url(forResource: "portal", withExtension: "html", subdirectory: "portal")
            ?? Bundle.module.url(forResource: "portal", withExtension: "html")
        else {
            FileHandle.standardError.write(Data("portal: portal.html missing from the bundle\n".utf8))
            NSApp.terminate(nil)
            return
        }

        let config = WKWebViewConfiguration()
        // Nothing in the page needs to reach the network, and a HUD that
        // phones out at launch is a HUD nobody should install.
        config.suppressesIncrementalRendering = false

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let web = WKWebView(frame: frame, configuration: config)
        web.navigationDelegate = self
        // Transparent, or the page paints a white sheet over the desktop.
        // `drawsBackground` is not public API on WKWebView, and the
        // documented alternatives do not exist on macOS; every shipping
        // transparent WKWebView sets it this way.
        web.setValue(false, forKey: "drawsBackground")
        web.autoresizingMask = [.width, .height]
        self.web = web

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        // Above normal windows and above the HUD overlay, since a portal that
        // opens behind your editor is not a portal.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Click-through everywhere, always. There is nothing on this glass to
        // press: the only input is your hand in front of the camera.
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.contentView = web
        panel.orderFrontRegardless()
        self.panel = panel

        web.loadFileURL(html, allowingReadAccessTo: html.deletingLastPathComponent())

        tracker.onLandmarks = { [weak self] points in
            self?.push(points)
        }
        tracker.start()

        // Esc quits. The panel never takes focus, so this is a global monitor
        // rather than a key handler.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { Task { @MainActor in NSApp.terminate(nil) } }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { NSApp.terminate(nil); return nil }
            return event
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        ready = true
    }

    private func push(_ points: [LandmarkBridge.Point]?) {
        guard let web, ready else {
            if points != nil { droppedBeforeReady += 1 }
            return
        }
        let arg = points.map { LandmarkBridge.json($0) } ?? "null"
        // No completion handler: at 30fps the callback allocation is the
        // expensive part and there is nothing to do with the result.
        web.evaluateJavaScript("window.chewbaccaHands&&window.chewbaccaHands(\(arg))")
    }

    func applicationWillTerminate(_: Notification) {
        tracker.stop()
        if droppedBeforeReady > 0 {
            FileHandle.standardError.write(
                Data("portal: dropped \(droppedBeforeReady) frames before the page loaded\n".utf8))
        }
    }
}

let app = NSApplication.shared
// Accessory, not regular: no Dock icon, no menu bar, never steals focus.
app.setActivationPolicy(.accessory)
let controller = PortalController()
app.delegate = controller
app.run()
