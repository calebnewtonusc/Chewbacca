import AppKit
import BobHUDKit
import SwiftUI
import os

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
    /// The conversation, as a window. See `ChatWindow`.
    private var chat: ChatWindow?
    /// Two globe presses in a row, which is the way out. See `DoubleTap`.
    private var taps = DoubleTap()
    /// Which app was in front when the bar opened, so it can be given back.
    private var previousApp: NSRunningApplication?
    private var hotKeyMonitor: Any?
    private var escMonitor: Any?
    private var localEscMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var localFlagsMonitor: Any?
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
    /// The listening mode chosen from the menu, kept across launches.
    ///
    /// Only a mode the person picked is ever restored: a first launch is
    /// still off, which is what the menu's comment promises. Before this,
    /// every relaunch came up deaf and the first press of the evening did
    /// nothing, on 2026-09-19 five times in a row.
    private static let listeningKey = "hud.listening"
    /// How long a missed utterance stays on the pill. The person just let go
    /// of the key, so they are looking. 3s: guessed, never measured.
    private static let missedHold: TimeInterval = 3
    /// How long "nothing is listening" stays on the pill. It replaces a card
    /// that stayed 9s at 460 wide; this is twelve words. 6s: guessed, never
    /// measured.
    private static let nobodyHold: TimeInterval = 6

    func applicationDidFinishLaunching(_ notification: Notification) {
        let overlay = OverlayWindow(content: OverlayView(model: model))
        self.overlay = overlay
        overlay.show()

        setUpCommandBar()
        setUpChat()
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

        // Every event goes up the socket, and if nobody is there the person is
        // told rather than left wondering.
        //
        // Without this, asking for something with nothing listening did
        // absolutely nothing: no panel, no error, no ring change. That is the
        // worst failure a front door can have, because it is indistinguishable
        // from the request having been understood and ignored.
        model.onEvent = { [weak self, weak server] event in
            let delivered = server?.send(event.line) ?? false
            guard !delivered else { return }
            switch event {
            case .heard, .typed:
                Task { @MainActor in self?.reportNobodyListening() }
            default:
                // A click on a panel nobody is listening to is not worth a
                // notice: the control already wrote to the panel's own data and
                // did the visible half of its job.
                break
            }
        }
        // The X on the pill, or Escape, while the sentence is still the
        // person's: stop the microphone. A cancel while working goes up the
        // socket from the model.
        model.onPillCancel = { [weak self] _ in
            self?.voice.cancelPush()
        }
        setUpVoice()
        restoreListening()

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
            hotKeyMonitor, escMonitor, localEscMonitor, mouseMonitor,
            localMouseMonitor, flagsMonitor, localFlagsMonitor, barMonitor,
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
                // It also goes back to whoever sent it now: a sender that
                // cannot tell a typo from success will keep making the typo.
                model.warn(String(describing: error))
                model.onEvent?(.problem(String(describing: error)))
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
            Task { @MainActor in self?.escape() }
        }
        // The conversation panel makes this app active while it is open, and
        // an active app sees its own keys locally, not through the global
        // monitor above. Escape there closes the panel and nothing else.
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.model.chatOpen else { return event }
            Task { @MainActor in self.model.closeChat() }
            return nil
        }

        // Follow the pointer so the glass only becomes solid over a surface.
        // Without this the overlay swallows every scroll on the display.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateInteractive()
                self?.trackPointer()
            }
        }

        // A global monitor only sees events delivered to *other* apps, so the
        // moment the glass goes solid it stops reporting. Without this the
        // overlay would stay interactive forever after the first hover, and
        // scrolling would break again the instant you touched a surface.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor in
                self?.updateInteractive()
                self?.trackPointer()
            }
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
                    self.dispatch(asked, typed: true)
                    self.restoreFocus()
                }
            },
            onDismiss: { [weak self] in
                Task { @MainActor in self?.restoreFocus() }
            })
    }

    /// The conversation panel, and the pill's other half.
    ///
    /// Built at launch like the command bar, for the same reason: a click
    /// on the pill has to open something at once, and constructing a panel
    /// under the click is not at once.
    private func setUpChat() {
        chat = ChatWindow(
            model: model,
            onSubmit: { [weak self] asked in
                Task { @MainActor in self?.dispatch(asked, typed: true) }
            },
            onSpeak: { [weak self] text in
                // Read aloud on request: the bridge owns the voice, so this
                // goes up as an action on the turn rather than being spoken
                // here.
                Task { @MainActor in
                    self?.model.onEvent?(.action(name: "say", component: "turn", payload: ["text": .string(text)]))
                }
            },
            onStop: { [weak self] in
                Task { @MainActor in self?.model.cancelRun() }
            },
            onDismiss: { [weak self] in
                Task { @MainActor in self?.model.closeChat() }
            })
        model.onChatOpen = { [weak self] in
            guard let self else { return }
            self.previousApp = NSWorkspace.shared.frontmostApplication
            self.overlay?.show()
            self.chat?.present()
        }
        model.onChatClose = { [weak self] in
            guard let self, let chat = self.chat else { return }
            if chat.isVisible { chat.orderOut(nil) }
            self.restoreFocus()
        }
    }

    /// Say that the request went nowhere.
    ///
    /// Drawn by the display itself, which is the only thing in this system that
    /// can still speak when the other end is gone. It expires on its own,
    /// because the pill is a notice rather than something to dismiss, and the
    /// ring stays red after it.
    private func reportNobodyListening() {
        model.setPresence(.failed, amplitude: 0)
        model.fail("Nothing is listening. Run: hud listen", hold: Self.nobodyHold)
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
    /// socket. The words themselves go on the pill: every partial as it is
    /// revised, and the sentence the moment it is sent.
    private func setUpVoice() {
        voice.onSignal = { [weak self] signal in
            Task { @MainActor in
                guard let self else { return }
                switch signal {
                case .listening(let on):
                    // Voice.swift sends `.heard` and then `.listening(false)`,
                    // and `.failed` and then `.listening(false)`, in that
                    // order. A sentence already sent has put the pill in
                    // working and the ring in thinking; a failure is on its
                    // hold. Both keep the ring where it is: the model takes a
                    // failed pill down on any return to dormant.
                    if !on, self.model.pill.phase == .working || self.model.pill.phase == .failed {
                        return
                    }
                    self.model.setPresence(on ? .attentive : .dormant, amplitude: 0)
                    if on && self.voice.mode == .pushToTalk { self.model.beginHearing() }

                case .level(let level):
                    // Only claim to be hearing something above the noise floor.
                    // A ring that reacts to a fan is a ring nobody believes.
                    if level > 0.18 {
                        self.model.setPresence(.hearing, amplitude: level)
                    } else if self.model.presence == .hearing {
                        self.model.setPresence(.attentive, amplitude: 0)
                    }

                case .partial(let text):
                    self.model.hear(partial: text)

                case .heard(let text):
                    // On the pill and up the socket in the same breath. There
                    // was a one second cancel window here; it was a second on
                    // every request, for a wrong transcript that the X on the
                    // pill can still stop once the run is under way. Asked
                    // for 2026-09-19: "release the button, think, reply,
                    // execute task as quickly as possible."
                    self.model.heard(text)
                    self.dispatch(text, typed: false)

                case .failed(let message):
                    // The pill is the notice. `warn` would draw it a second
                    // time, inside whatever panel happens to be open.
                    self.model.setPresence(.failed, amplitude: 0)
                    self.model.fail(message, hold: Self.missedHold)
                }
            }
        }

        // Hold the globe key to talk.
        //
        // `fn` rather than a letter combination because it is a modifier nobody
        // else has claimed, it cannot collide with what you are typing into the
        // app underneath, and holding it is a gesture rather than a shortcut to
        // remember. Nothing is captured until it goes down.
        //
        // Two monitors, because a global one sees only the events other apps
        // get. Click the pill and this app is the active one, and from then
        // on the key went nowhere; a release that landed here while the
        // press had been seen globally also left the microphone open.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            let down = event.modifierFlags.contains(.function)
            Task { @MainActor in self?.globe(down: down) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            let down = event.modifierFlags.contains(.function)
            Task { @MainActor in self?.globe(down: down) }
            return event
        }
    }

    /// The globe key's state, from either monitor. Every flags change is
    /// forwarded, no memory of the last one kept: `beginPush` does nothing
    /// while a turn is open and `endPush` nothing while the microphone is
    /// shut, so a repeat is harmless, and a flag that tracked the key here
    /// could only ever drift from the truth after a missed event, which is
    /// the one case that matters.
    private func globe(down: Bool) {
        // Persisted, so a key that stops working can be told apart from a
        // key that stopped arriving: on 2026-09-19 two presses produced no
        // trace at all and there was no way to know which.
        Self.keys.notice("voice.key down=\(down) mode=\(self.voice.mode.rawValue, privacy: .public)")
        guard voice.mode == .pushToTalk else { return }
        if down {
            // The same key twice, quickly, is out rather than in.
            if taps.press() {
                Self.keys.notice("voice.key double")
                leave()
                return
            }
            voice.beginPush()
        } else {
            taps.release()
            voice.endPush()
        }
    }

    /// Two globe presses: out, whatever is up. The panel, the microphone, a
    /// run in flight, the voice and the glass, in one gesture. The
    /// conversation is kept for the next time the panel opens; forgetting
    /// it is the menu's job.
    private func leave() {
        if model.chatOpen { model.closeChat() }
        // The first of the two presses opened the microphone. Drop that
        // turn before its grace timer commits a stray syllable as a request.
        voice.cancelPush()
        switch model.pill.phase {
        case .hearing, .heard: model.cancelRun()
        default: break
        }
        dismissAll(forgetting: false, always: true)
    }

    private static let keys = Logger(subsystem: "bob.hud", category: "keys")

    /// Send a request up the socket. The microphone, the typed bar and the
    /// conversation panel all come here, so there is one path from asking
    /// to drawing rather than three that drift. `typed` goes up with the
    /// request, so the bridge can answer a typed question in writing rather
    /// than out loud.
    private func dispatch(_ text: String, typed: Bool) {
        model.setPresence(.thinking, amplitude: 0)
        model.asked(text, typed: typed)
        model.onEvent?(typed ? .typed(text) : .heard(text))
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

    /// Tell the field where the hand is, so the band can part round it.
    private func trackPointer() {
        guard let screen = OverlayWindow.active else {
            model.point(at: nil, aspect: 1)
            return
        }
        let frame = screen.frame
        let mouse = NSEvent.mouseLocation
        let unit = CGPoint(
            x: (mouse.x - frame.minX) / frame.width,
            y: (frame.maxY - mouse.y) / frame.height)
        model.point(at: unit, aspect: frame.width / max(frame.height, 1))
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

    /// Escape. What it takes back depends on where the request is.
    private func escape() {
        // The panel first. Escape with the conversation up puts it back
        // into the pill; it does not also clear the glass under it.
        if model.chatOpen {
            model.closeChat()
            return
        }
        switch model.pill.phase {
        case .hearing, .heard:
            // Still the person's sentence. `cancelRun` goes through
            // `onPillCancel`, which stops the microphone, and then takes the
            // pill down.
            model.cancelRun()
        default:
            dismissAll()
        }
    }

    /// Take everything down. `forgetting` also drops the conversation;
    /// `always` goes ahead with an empty glass, for the band and the voice,
    /// which are not on it.
    private func dismissAll(forgetting: Bool = true, always: Bool = false) {
        guard always || !model.isEmpty else { return }
        // A run in flight is stopped rather than hidden, with the same
        // `e stop run` line the X on the pill sends. The bridge answers with
        // `p failed`; what was drawn goes with the reset.
        if model.pill.phase == .working {
            model.onEvent?(.action(name: "stop", component: "run", payload: [:]))
        }
        // `x`: the bridge hushes the voice on it and shows nothing after.
        model.onEvent?(.dismissed)
        model.reset()
        if forgetting { model.clearChat() }
    }

    private func setUpMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "sparkles.rectangle.stack",
            accessibilityDescription: "Chewbacca")

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

        let chatItem = NSMenuItem(
            title: "Open the conversation", action: #selector(chatFromMenu), keyEquivalent: "")
        chatItem.target = self
        menu.addItem(chatItem)

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
        UserDefaults.standard.set(raw, forKey: Self.listeningKey)
        listen(mode)
    }

    /// Bring the mode chosen last time back, menu tick and all.
    private func restoreListening() {
        guard let raw = UserDefaults.standard.string(forKey: Self.listeningKey),
              let mode = VoiceListener.Mode(rawValue: raw), mode != .off
        else { return }
        listen(mode)
    }

    private func listen(_ mode: VoiceListener.Mode) {
        voice.setMode(mode)
        // Permissions and the recogniser's first start happen now, on the
        // person's choice, not under their first sentence.
        if mode == .pushToTalk { voice.prepare() }
        for entry in voiceMenu?.items ?? [] {
            entry.state = (entry.representedObject as? String) == mode.rawValue ? .on : .off
        }
        if mode == .off { model.setPresence(.dormant, amplitude: 0) }
    }

    @objc private func askFromMenu() { showCommandBar() }
    @objc private func chatFromMenu() { model.openChat() }
    @objc private func toggleFromMenu() { toggle() }
    @objc private func clearFromMenu() { dismissAll() }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Chewbacca could not start"
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
