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
final class PortalController: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var panel: NSPanel?
    private var web: WKWebView?
    private let tracker = HandTracker()
    private var ready = false
    /// Frames dropped because the page had not finished loading. Reported on
    /// quit, because "it did nothing" and "it did nothing for the first two
    /// seconds" are different bugs.
    private var droppedBeforeReady = 0
    /// What the portal opens onto, or nil for a plain void. Written by
    /// `bin/portal` and polled, rather than passed as a launch argument,
    /// because the voice agent arms a portal that is usually already running.
    /// The most recent pupils, held so they ride out with the next landmark
    /// frame. Both come from the same camera frame, and splitting them into
    /// two messages would let the web layer pair a hand with stale eyes.
    private var lastEyes: LandmarkBridge.Eyes?
    private var armed: String?
    private var armTimer: Timer?
    private static let armFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chewbacca/portal-target")
    /// How much parallax correction to apply, 0 to 1. A file rather than a
    /// launch argument for the same reason the target is: the portal is
    /// usually already running when somebody wants to change it, and finding
    /// the right value means moving a hand and watching, not restarting.
    private static let gainFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chewbacca/portal-gain")
    private static let sizeFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chewbacca/portal-size")
    private static let reachFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chewbacca/portal-reach")
    private static let handFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chewbacca/portal-hand")
    private static let trailFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".chewbacca/portal-trail")
    private var gain: Double?
    private var size: Double?
    private var reach: Double?
    private var hand: Double?
    private var trail: Double?

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
        config.userContentController.add(self, name: "portal")
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
        // Setting this is what turns the face pass on; it is opt in, so a
        // consumer that does not want eyes does not pay for them.
        tracker.onEyes = { [weak self] eyes in
            self?.lastEyes = eyes
        }
        tracker.start()

        // Poll rather than watch. The file changes at human speed, a quarter
        // second is imperceptible next to drawing a circle, and an FSEvents
        // stream for one path is more machinery than the problem deserves.
        readArm()
        readGain()
        readSize()
        readReach()
        readHand()
        armTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                self.readArm()
                self.readGain()
                self.readSize()
                self.readReach()
                self.readHand()
            self.readTrail()
            }
        }

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
        applyArm()
        if let g = gain {
            web?.evaluateJavaScript("window.chewbaccaGain&&window.chewbaccaGain(\(g))")
        }
        if let sz = size {
            web?.evaluateJavaScript("window.chewbaccaSize&&window.chewbaccaSize(\(sz))")
        }
        if let rh = reach {
            web?.evaluateJavaScript("window.chewbaccaReach&&window.chewbaccaReach(\(rh))")
        }
        if let hd = hand {
            web?.evaluateJavaScript("window.chewbaccaHand&&window.chewbaccaHand(\(hd))")
        }
        if let tr = trail {
            web?.evaluateJavaScript("window.chewbaccaTrail&&window.chewbaccaTrail(\(tr))")
        }
    }

    /// `bin/portal open --app Notes` writes the name here; `portal close`
    /// empties it.
    private func readArm() {
        let text = (try? String(contentsOf: Self.armFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let next = (text?.isEmpty ?? true) ? nil : text
        guard next != armed else { return }
        armed = next
        applyArm()
        // Launching takes seconds, so get it up now rather than in the
        // moment the circle closes. By the time the portal opens the window
        // exists and only has to be moved.
        if let name = next {
            // NOT MainActor.assumeIsolated. That fatal-errors when it is
            // not actually on the main actor, which a global queue never is,
            // so the app crashed on launch the moment the arm file was
            // non-empty. It launched fine while the file was empty, which is
            // what made it look like the bundling had broken instead.
            DispatchQueue.global(qos: .userInitiated).async {
                _ = WindowPlacer.ensureRunning(appName: name)
            }
        }
    }

    private func readGain() {
        let text = (try? String(contentsOf: Self.gainFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let value = Double(text) else { return }
        guard gain != value else { return }
        gain = value
        guard ready, let web else { return }
        web.evaluateJavaScript("window.chewbaccaGain&&window.chewbaccaGain(\(value))")
    }

    private func readSize() {
        let text = (try? String(contentsOf: Self.sizeFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let value = Double(text), size != value else { return }
        size = value
        guard ready, let web else { return }
        web.evaluateJavaScript("window.chewbaccaSize&&window.chewbaccaSize(\(value))")
    }

    private func readReach() {
        let text = (try? String(contentsOf: Self.reachFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let value = Double(text), reach != value else { return }
        reach = value
        guard ready, let web else { return }
        web.evaluateJavaScript("window.chewbaccaReach&&window.chewbaccaReach(\(value))")
    }

    private func readHand() {
        let text = (try? String(contentsOf: Self.handFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let value = Double(text), hand != value else { return }
        hand = value
        guard ready, let web else { return }
        web.evaluateJavaScript("window.chewbaccaHand&&window.chewbaccaHand(\(value))")
    }

    private func readTrail() {
        let text = (try? String(contentsOf: Self.trailFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, let value = Double(text), trail != value else { return }
        trail = value
        guard ready, let web else { return }
        web.evaluateJavaScript("window.chewbaccaTrail&&window.chewbaccaTrail(\(value))")
    }

    private func applyArm() {
        guard ready, let web else { return }
        let arg = armed.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" } ?? "null"
        web.evaluateJavaScript("window.chewbaccaArm&&window.chewbaccaArm(\(arg))")
    }

    // MARK: WKScriptMessageHandler

    nonisolated func userContentController(
        _: WKUserContentController, didReceive message: WKScriptMessage
    ) {
        // WebKit delivers script messages on the main thread, and in the 15.x
        // SDK `WKScriptMessage.body` became main-actor isolated, so reading it
        // from a `nonisolated` method is an error on Swift 6.1.2: the Portal
        // target did not compile and it took `swift test` for the whole package
        // down with it. `assumeIsolated` states the guarantee WebKit already
        // makes rather than hopping, which would reorder the message against
        // the `Task` below.
        //
        // `readArm` above says NOT to use `assumeIsolated`, and that is the
        // same rule, not a contradiction: it traps unless the caller really is
        // on the main actor, which a global queue never is and which WebKit
        // always is. Before copying either line, check which of those the
        // caller is.
        MainActor.assumeIsolated { handle(message) }
    }

    private func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String
        else { return }
        Task { @MainActor in
            guard event == "opened",
                  let name = body["armed"] as? String,
                  let x = body["x"] as? Double,
                  let y = body["y"] as? Double,
                  let r = body["r"] as? Double
            else { return }
            let placed = WindowPlacer.place(
                appName: name, centerX: x, centerY: y, radius: r)
            if !placed {
                FileHandle.standardError.write(Data(
                    "portal: could not place \(name). Grant Accessibility to Portal.app in System Settings, Privacy and Security.\n".utf8))
            }
        }
    }

    private func push(_ points: [LandmarkBridge.Point]?) {
        guard let web, ready else {
            if points != nil { droppedBeforeReady += 1 }
            return
        }
        let arg = points.map { LandmarkBridge.json($0) } ?? "null"
        // No completion handler: at 30fps the callback allocation is the
        // expensive part and there is nothing to do with the result.
        let eyesArg: String
        if let e = lastEyes {
            eyesArg = "{\"left\":{\"x\":\(round(e.left.x * 1e6) / 1e6),\"y\":\(round(e.left.y * 1e6) / 1e6)},"
                + "\"right\":{\"x\":\(round(e.right.x * 1e6) / 1e6),\"y\":\(round(e.right.y * 1e6) / 1e6)}}"
        } else {
            eyesArg = "null"
        }
        web.evaluateJavaScript(
            "window.chewbaccaHands&&window.chewbaccaHands(\(arg),\(eyesArg))")
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
