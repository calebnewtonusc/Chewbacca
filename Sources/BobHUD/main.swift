import AppKit
import BobHUDKit
import SwiftUI

/// BobHUD: a layer of glass over everything, with things drawn on it.
///
/// Listen on a Unix socket, parse Bob Lines, place surfaces around the screen,
/// and send events back when someone uses a control. No browser, no window that
/// steals focus, no model in this process at all.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = OverlayModel()
    private var overlay: OverlayWindow?
    private var server: SocketServer?
    private var statusItem: NSStatusItem?
    private var voiceMenu: NSMenu?
    private var commandBar: CommandBarWindow?
    /// Which app was in front when the bar opened, so it can be given back.
    private var previousApp: NSRunningApplication?
    private var hotKeyMonitor: Any?
    private var escMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var flagsMonitor: Any?
    private var barMonitor: Any?
    private var reticleDown: Any?
    private var reticleDrag: Any?
    private var reticleUp: Any?
    /// Where a reticle drag began, in screen points. Nil when not dragging.
    private var reticleOrigin: CGPoint?
    private let voice = VoiceListener()
    /// Whether the push-to-talk key is currently down, so a flags change that
    /// does not involve it is ignored.
    private var pushing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = OverlayWindow(content: OverlayView(model: model))
        self.overlay = overlay
        overlay.show()

        setUpCommandBar()
        setUpReticle()
        setUpMenuBar()
        setUpKeys()
        observeScreenChanges()

        let server = SocketServer(path: SocketServer.defaultPath) { [weak self] event in
            // The socket runs on its own queue; every touch of the model has to
            // happen on the main actor.
            Task { @MainActor in self?.handle(event) }
        }
        self.server = server

        model.onEvent = { [weak server] event in server?.send(event.line) }
        setUpVoice()

        do {
            try server.start()
        } catch {
            presentFatal(error)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        voice.setMode(.off)
        let monitors = [
            hotKeyMonitor, escMonitor, mouseMonitor,
            localMouseMonitor, flagsMonitor, barMonitor,
            reticleDown, reticleDrag, reticleUp,
        ]
        for monitor in monitors.compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handle(_ event: SocketServer.Event) {
        switch event.kind {
        case .began:
            // A new connection does *not* clear the glass.
            //
            // It used to, on the reasoning that two agents drawing at once is a
            // race and the last one in should win. That was wrong once surfaces
            // became addressable by name: every sentence you say to an agent is
            // a new connection, so wiping on connect meant a panel could never
            // survive long enough to be updated, and "change that chart" always
            // came out as "draw a new chart from nothing".
            //
            // Named surfaces settle the race on their own. Two agents writing to
            // different names cannot collide, and two writing to the same name
            // were always going to fight whatever this did. Clearing stays
            // available and stays deliberate: `- <surface>`, Escape, or the menu.
            overlay?.show()

        case .line(let line):
            do {
                if let op = try LineParser.parse(line) {
                    model.apply(op)
                    updateInteractive()
                }
            } catch {
                // A malformed line degrades one component rather than clearing
                // the glass, which is the same choice the web renderer makes.
                model.warn(String(describing: error))
            }

        case .ended:
            break

        case .failed(let message):
            model.warn(message)
        }
    }

    /// Option-Command-Space hides and shows everything. Escape clears it.
    ///
    /// Global monitors rather than a registered hot key, because registering one
    /// system-wide needs Accessibility permission, and a panel you can summon is
    /// not worth a permission prompt on first launch.
    private func setUpKeys() {
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.modifierFlags.contains([.option, .command]),
                  event.keyCode == 49 // space
            else { return }
            Task { @MainActor in self?.toggle() }
        }

        // Option-Space opens the command bar.
        //
        // Not Command-Space, which is Spotlight on every Mac, and not
        // Option-Command-Space, which already hides the glass. This is a global
        // monitor rather than a registered hot key for the same reason as the
        // others: registering one system-wide needs Accessibility, and a front
        // door is not worth a permission prompt on first launch.
        barMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.command),
                  event.keyCode == 49
            else { return }
            Task { @MainActor in self?.showCommandBar() }
        }

        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return } // escape
            Task { @MainActor in self?.dismissAll() }
        }

        // Follow the pointer so the glass only becomes solid over a surface.
        // Without this the overlay swallows every scroll on the display.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.updateInteractive() }
        }

        // A global monitor only sees events delivered to *other* apps, so the
        // moment the glass goes solid it stops reporting. Without this the
        // overlay would stay interactive forever after the first hover, and
        // scrolling would break again the instant you touched a surface.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor in self?.updateInteractive() }
            return event
        }
    }

    /// The typed front door.
    ///
    /// Built eagerly at launch rather than on first use. The spec puts the
    /// strictest performance contract in the system on this surface, under
    /// 100ms, and constructing an `NSPanel` with a SwiftUI hosting view the
    /// first time somebody hits the key is well over that on a cold app.
    private func setUpCommandBar() {
        commandBar = CommandBarWindow(
            onSubmit: { [weak self] asked in
                Task { @MainActor in
                    guard let self else { return }
                    self.model.setPresence(.thinking, amplitude: 0)
                    // The same event a spoken request produces, so there is one
                    // path from asking to drawing rather than two that drift.
                    self.model.onEvent?(.heard(asked))
                    self.restoreFocus()
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor in self?.restoreFocus() }
            })
    }

    /// Give the app back the focus the bar took.
    ///
    /// Summoning the bar activates this app, which is the honest cost of a
    /// window you can type in. Not handing focus back afterwards would be the
    /// dishonest part: the person was in the middle of something.
    private func restoreFocus() {
        previousApp?.activate()
        previousApp = nil
    }

    private func showCommandBar() {
        previousApp = NSWorkspace.shared.frontmostApplication
        overlay?.show()
        commandBar?.present()
    }

    /// Hearing, and what to do about it.
    ///
    /// The listener is deliberately dumb: it produces text and a level and knows
    /// nothing about surfaces or agents. This is where it becomes visible, and
    /// the mapping is the whole design of the ring made concrete. Listening is
    /// `attentive`, a raised level is `hearing`, and a finished sentence is
    /// `thinking`, because from the person's side the request is now in flight
    /// whether or not anything is actually listening on the other end of the
    /// socket.
    private func setUpVoice() {
        voice.onSignal = { [weak self] signal in
            Task { @MainActor in
                guard let self else { return }
                switch signal {
                case .listening(let on):
                    self.model.setPresence(on ? .attentive : .dormant, amplitude: 0)

                case .level(let level):
                    // Only claim to be hearing something above the noise floor.
                    // A ring that reacts to a fan is a ring nobody believes.
                    if level > 0.18 {
                        self.model.setPresence(.hearing, amplitude: level)
                    } else if self.model.presence == .hearing {
                        self.model.setPresence(.attentive, amplitude: 0)
                    }

                case .heard(let text):
                    self.model.setPresence(.thinking, amplitude: 0)
                    self.model.onEvent?(.heard(text))

                case .failed(let message):
                    self.model.warn(message)
                    self.model.setPresence(.failed, amplitude: 0)
                }
            }
        }

        // Hold the globe key to talk.
        //
        // `fn` rather than a letter combination because it is a modifier nobody
        // else has claimed, it cannot collide with what you are typing into the
        // app underneath, and holding it is a gesture rather than a shortcut to
        // remember. Nothing is captured until it goes down.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            let down = event.modifierFlags.contains(.function)
            Task { @MainActor in
                guard let self, self.voice.mode == .pushToTalk else { return }
                if down && !self.pushing {
                    self.pushing = true
                    self.voice.beginPush()
                } else if !down && self.pushing {
                    self.pushing = false
                    self.voice.endPush()
                }
            }
        }
    }

    /// Point at something and it becomes the subject.
    ///
    /// This is deixis, and it is what makes fragmentary requests possible. "Why
    /// is this failing" while pointing at a stack trace is one second of effort
    /// and carries more precise context than a paragraph of typing. Without it
    /// every request begins with the person performing context transfer, and
    /// that transfer is most of the cost of most interactions.
    ///
    /// Hold Option-Command and drag. The region is drawn as it is made, and on
    /// release it goes up the socket as coordinates.
    ///
    /// Coordinates rather than pixels: the display deliberately has no screen
    /// recording permission, and asking for one so it can crop a rectangle it
    /// already knows the bounds of would be a poor trade. Whatever is listening
    /// can look at the region itself if it needs to see it.
    private func setUpReticle() {
        let held: (NSEvent) -> Bool = { event in
            event.modifierFlags.contains([.option, .command])
        }

        reticleDown = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard held(event) else { return }
            Task { @MainActor in
                self?.reticleOrigin = Self.flipped(NSEvent.mouseLocation)
            }
        }

        reticleDrag = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, let origin = self.reticleOrigin else { return }
                let rect = Self.rect(from: origin, to: Self.flipped(NSEvent.mouseLocation))
                // Drawn live, and pinned, because a mark that expired mid-drag
                // would flicker under the cursor making it.
                self.model.mark(
                    id: "reticle", rect: rect, label: "", tone: nil, life: 0)
            }
        }

        reticleUp = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, let origin = self.reticleOrigin else { return }
                self.reticleOrigin = nil
                let rect = Self.rect(from: origin, to: Self.flipped(NSEvent.mouseLocation))
                // A click rather than a drag. Not a region, and treating it as
                // one would send a 2-point rectangle nobody meant.
                guard rect.width > 12, rect.height > 12 else {
                    self.model.apply(.unmark(id: "reticle"))
                    return
                }
                self.model.mark(
                    id: "reticle", rect: rect, label: "this", tone: nil, life: 20)
                self.model.onEvent?(.region(rect))
            }
        }
    }

    /// AppKit's mouse location has a bottom-left origin and everything a person
    /// would compare it against, including every screenshot, has a top-left one.
    private static func flipped(_ point: NSPoint) -> CGPoint {
        guard let screen = OverlayWindow.active else { return point }
        return CGPoint(x: point.x, y: screen.frame.maxY - point.y)
    }

    private static func rect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y))
    }

    private func updateInteractive() {
        // Following the pointer across displays happens here rather than on a
        // timer: the mouse monitor already fires on every move, and refitting is
        // a no-op when the frame is already right.
        overlay?.fitToScreen()
        overlay?.updateInteractive(surfaces: model.frames, mouse: NSEvent.mouseLocation)
    }

    /// The glass has to follow the display it is over.
    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.overlay?.fitToScreen() }
        }
    }

    private func toggle() {
        guard let overlay else { return }
        if overlay.isVisible { overlay.orderOut(nil) } else { overlay.show() }
    }

    private func dismissAll() {
        guard !model.isEmpty else { return }
        model.onEvent?(.dismissed)
        model.reset()
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles.rectangle.stack",
            accessibilityDescription: "Bob HUD")

        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Show or hide", action: #selector(toggleFromMenu), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.option, .command]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let askItem = NSMenuItem(
            title: "Ask for something", action: #selector(askFromMenu), keyEquivalent: " ")
        askItem.keyEquivalentModifierMask = [.option]
        askItem.target = self
        menu.addItem(askItem)

        let clearItem = NSMenuItem(
            title: "Clear everything", action: #selector(clearFromMenu), keyEquivalent: "\u{1b}")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(.separator())

        // Listening is off until asked for.
        //
        // A microphone that opens on first launch is the kind of thing that gets
        // a tool uninstalled, however good its reasons. The menu is where the
        // person decides, and the three options are honest about their cost.
        let listening = NSMenuItem(title: "Listening", action: nil, keyEquivalent: "")
        let listenMenu = NSMenu()
        for (title, mode) in [
            ("Off", VoiceListener.Mode.off),
            ("Hold the globe key to talk", .pushToTalk),
            ("Always, on a wake word", .wake),
        ] {
            let entry = NSMenuItem(
                title: title, action: #selector(setListening(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = voice.mode == mode ? .on : .off
            listenMenu.addItem(entry)
        }
        listening.submenu = listenMenu
        menu.addItem(listening)
        voiceMenu = listenMenu
        menu.addItem(.separator())

        let socket = NSMenuItem(title: SocketServer.defaultPath, action: nil, keyEquivalent: "")
        socket.isEnabled = false
        menu.addItem(socket)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        item.menu = menu
        statusItem = item
    }

    @objc private func setListening(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = VoiceListener.Mode(rawValue: raw)
        else { return }
        voice.setMode(mode)
        for entry in voiceMenu?.items ?? [] {
            entry.state = (entry.representedObject as? String) == raw ? .on : .off
        }
        if mode == .off { model.setPresence(.dormant, amplitude: 0) }
    }

    @objc private func askFromMenu() { showCommandBar() }
    @objc private func toggleFromMenu() { toggle() }
    @objc private func clearFromMenu() { dismissAll() }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Bob HUD could not start"
        alert.informativeText =
            "\(error.localizedDescription)\n\nSocket: \(SocketServer.defaultPath)"
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
