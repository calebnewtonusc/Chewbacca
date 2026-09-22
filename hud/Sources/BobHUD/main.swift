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
    let model = OverlayModel()
    var overlay: OverlayWindow?
    private var server: SocketServer?
    private var statusItem: NSStatusItem?
    private var voiceMenu: NSMenu?
    private var pushKeyMenu: NSMenu?
    private var commandBar: CommandBarWindow?
    /// The conversation, as a window. See `ChatWindow`.
    private var chat: ChatWindow?
    /// Two globe presses in a row, which is the way out. See `DoubleTap`.
    private var taps = DoubleTap()
    /// Whether anything above the noise floor reached the microphone this
    /// turn. A press that heard nothing was an accident, and is dropped
    /// without a word.
    private var heardSound = false
    /// Which app was in front when the bar opened, so it can be given back.
    private var previousApp: NSRunningApplication?
    private var hotKeyMonitor: Any?
    private var escMonitor: Any?
    private var localEscMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var localFlagsMonitor: Any?
    private var flagsMonitor: Any?
    private var barMonitor: Any?
    private var reticleDown: Any?
    private var reticleDrag: Any?
    private var reticleUp: Any?
    /// Where a reticle drag began, in screen points. Nil when not dragging.
    private var reticleOrigin: CGPoint?
    // The dictation bubble. Internal rather than private because the whole of
    // its behaviour lives in Dictation.swift, and stored properties cannot be
    // added in an extension.
    var bubbleDownMonitor: Any?
    var bubbleDragMonitor: Any?
    var bubbleUpMonitor: Any?
    var localBubbleDownMonitor: Any?
    var localBubbleDragMonitor: Any?
    var localBubbleUpMonitor: Any?
    /// The field each bound bubble is following, by bubble id.
    var bubbleTargets: [String: TextTarget] = [:]
    /// Where the field was and where the bubble was, at the moment of the
    /// drop, so the bubble moves by the field's delta rather than jumping to
    /// the field's own edge. See the follow loop in `Dictation.swift`.
    var bubbleAnchors: [String: Anchor] = [:]

    struct Anchor {
        let field: CGPoint
        let bubble: CGPoint
    }
    /// The bubble whose dictation turn is open, or nil. One at a time: there is
    /// one microphone.
    var dictating: String?
    /// Follows every bound field at 10Hz. One task for all bubbles.
    var bubbleFollow: Task<Void, Never>?
    /// Which bubble is under the pointer with the button down, and where the
    /// press landed, so a release can tell a click from a drag.
    var bubbleDragID: String?
    var bubbleDragFrom: CGPoint?
    /// Where the bubble's centre is relative to the pointer, so it does not
    /// jump to centre itself under the cursor on the first move.
    var bubbleDragOffset: CGSize = .zero
    /// True once a press has moved far enough to be a drag.
    var bubbleDragMoved = false
    /// Closes a dictation turn nobody is talking into. See `dictationSilence`.
    var dictationQuiet: Task<Void, Never>?
    /// Which insert each bubble is waiting on, so the clean-up hop and its
    /// own timeout cannot both write. See `heard(_:on:)`.
    var pendingInsert: [String: Pending] = [:]
    var insertToken = 0

    /// A sentence heard, waiting on the clean-up hop or its timeout.
    struct Pending {
        let token: Int
        /// What goes in if the bridge says nothing: the transcript, punctuated
        /// by `spoken`. Held here rather than read back off the bubble, because
        /// the bubble's words are cleared the moment it leaves `live`.
        let text: String
    }
    // `voice` is internal, not private: the dictation fork in
    // Dictation.swift drives the same listener, and it is one microphone.
    let voice = VoiceListener()
    private let handTracker = HandTracker()
    /// The tone that says the press was heard. See `Earcon`.
    private let earcon = Earcon()
    private static let earconKey = "hud.earcon"
    /// Off unless turned on from the menu. It shipped on, and the first day
    /// of use ended with "get rid of the little beep ... just the sound
    /// effect when i release push to talk" (2026-09-20): the band moving
    /// and the pill's line are receipt enough, and a tone on every release
    /// is a tone on every sentence of a conversation.
    private static var earconOn: Bool {
        UserDefaults.standard.bool(forKey: earconKey)
    }
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
        setUpBubbles()
        setUpHands()
        setUpMenuBar()
        setUpKeys()
        observeScreenChanges()
        observeFrontApp()

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
            case .clean(let id, _):
                // A bubble is holding a sentence waiting for a tidied version
                // from a bridge that is not there. Waiting out the budget would
                // be 1.5 seconds of nothing happening in front of somebody who
                // just finished speaking.
                Task { @MainActor in self?.nobodyToClean(id) }
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

        // Start the listener at launch rather than on the first keypress.
        //
        // `prime()` inside it opens the model session and has the prompt read
        // before its socket is even open, so starting it lazily means the
        // first hold of the talk key waits for a Python start, a 70KB prompt
        // build and a whole model round trip with the person standing there.
        // Login is not a moment anybody is waiting on, so it is free here.
        //
        // Two seconds of grace first: a listener left from a previous run may
        // still be reconnecting, and two of them on one socket both answer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self, weak server] in
            guard let self, let server, !server.hasSubscribers else { return }
            _ = self.startListener()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
        voice.setMode(.off)
        handTracker.stop()
        let monitors = [
            hotKeyMonitor, escMonitor, localEscMonitor, mouseMonitor,
            localMouseMonitor, clickMonitor, localClickMonitor, flagsMonitor,
            localFlagsMonitor, barMonitor,
            reticleDown, reticleDrag, reticleUp,
            bubbleDownMonitor, bubbleDragMonitor, bubbleUpMonitor,
            localBubbleDownMonitor, localBubbleDragMonitor, localBubbleUpMonitor,
        ]
        bubbleFollow?.cancel()
        dictationQuiet?.cancel()
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
                    // The one op the display answers itself rather than
                    // drawing: it finishes a dictation turn that is already in
                    // flight, and the model holds no part of that.
                    if case .bubbleInsert(let id, let text) = op {
                        cleaned(id, text)
                    } else {
                        model.apply(op)
                    }
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

        case .subscribed:
            // A bridge that just connected has no idea how the panel's
            // switch is set, and a bridge restarted after the person turned
            // speech on for long answers would go back to pointing at the
            // hyper bar until the switch was touched again.
            model.onEvent?(model.preferenceEvent)

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

        // A click, anywhere. A guide is the one thing on the glass that
        // answers one: the person was told "press this", and the display has
        // to notice that they did without ever taking the click itself,
        // because the click belongs to the app underneath. Global for the
        // clicks that app gets, local for the rare one that lands while the
        // glass is solid over a panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.strike() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in self?.strike() }
            return event
        }
    }

    /// Hand the click to the guides, in the glass's own points.
    private func strike() {
        guard model.markers.contains(where: \.isGuide) else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = OverlayWindow.active, screen.frame.contains(mouse) else { return }
        let frame = screen.frame
        model.hit(at: CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y))
    }

    /// Which app the person is in, written where the tools can read it.
    ///
    /// `hud-guide` and `hud-context` ask the system what is in front, and
    /// while the conversation panel is open the answer is this app: the
    /// panel takes key, so a typed "where do I click" would have the screen
    /// reader reading the panel it was typed into. Every switch to another
    /// app is noted in one small file next to the socket, so a tool that
    /// finds this app in front knows which one to look at instead.
    private func observeFrontApp() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Self.noteFront(app)
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            Self.noteFront(app)
        }
    }

    nonisolated private static func noteFront(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let name = app.localizedName, !name.isEmpty
        else { return }
        let record: [String: Any] = [
            "name": name,
            "bundle": app.bundleIdentifier ?? "",
            "pid": Int(app.processIdentifier),
        ]
        let path = URL(fileURLWithPath: SocketServer.defaultPath)
            .deletingLastPathComponent().appendingPathComponent("front-app")
        guard let data = try? JSONSerialization.data(withJSONObject: record) else { return }
        try? data.write(to: path, options: .atomic)
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
            chat.conceal()
            self.restoreFocus()
        }
    }

    /// Start the listener rather than asking for it to be started.
    ///
    /// "Bro this should never happen, activating the fn key should by default
    /// mean it is listening."
    ///
    /// He is right, and the old behaviour broke the kit's own first rule: it
    /// printed "Run: hud listen" at him. Handing somebody a command is the
    /// single most common way an agent turns finished work into unfinished
    /// work, and a front door that answers a keypress with homework is the
    /// same failure wearing a UI.
    ///
    /// Pressing the key IS the request to listen. So the socket having nobody
    /// on the other end is not a thing to report, it is a thing to fix: spawn
    /// the listener, detached, and let the next event go through.
    ///
    /// Spawned at most once every few seconds. Without that, a listener that
    /// crashes on launch would be respawned on every keystroke, which is a
    /// fork bomb driven by a person's typing.
    private static var lastSpawn = Date.distantPast
    private static let spawnCooldown: TimeInterval = 4

    private func startListener() -> Bool {
        guard Date().timeIntervalSince(Self.lastSpawn) > Self.spawnCooldown else {
            return false
        }
        // Where the installer puts it, then the PATH, so this works on a
        // machine that laid the kit down somewhere else.
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/hud-listen").path,
            "/usr/local/bin/hud-listen",
            "/opt/homebrew/bin/hud-listen",
        ]
        guard let exe = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return false }

        Self.lastSpawn = Date()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        // Detached, and with its output kept. It used to go to nullDevice on
        // the grounds that this is a daemon rather than a command run for an
        // answer, which is true and still cost hours on 2026-09-21: speech was
        // reaching the microphone, transcribing correctly and then vanishing,
        // and there was no record anywhere of the listener's side of it
        // because this is where it was being thrown away. A daemon with no log
        // is a daemon you cannot debug.
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".chewbacca/logs")
        try? FileManager.default.createDirectory(
            at: logDir, withIntermediateDirectories: true)
        let logURL = logDir.appendingPathComponent("hud-listen.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            // Append rather than truncate: the run before the one that broke
            // is often the one that explains it.
            try? handle.seekToEnd()
            p.standardOutput = handle
            p.standardError = handle
        } else {
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
        }
        do { try p.run() } catch { return false }
        return true
    }

    /// Say that the request went nowhere, once starting it has been tried.
    ///
    /// Drawn by the display itself, which is the only thing in this system that
    /// can still speak when the other end is gone. It expires on its own,
    /// because the pill is a notice rather than something to dismiss, and the
    /// ring stays red after it.
    private func reportNobodyListening() {
        if startListener() {
            // Starting takes a moment, and the event that triggered this is
            // already gone. Say what is happening rather than nothing, and do
            // not colour the ring red for a state that is being resolved.
            model.setPresence(.thinking, amplitude: 0)
            model.fail("Starting the listener, say that again", hold: Self.nobodyHold)
            return
        }
        model.setPresence(.failed, amplitude: 0)
        model.fail("The listener will not start", hold: Self.nobodyHold)
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
                // A turn the person started by clicking a bubble belongs to
                // that bubble and to nothing else: the words go in the field
                // they pointed at, and the pill, the presence band and the
                // socket all stay out of it. See `Dictation.swift`.
                if self.dictating != nil, self.dictationSignal(signal) { return }
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
                    if on {
                        self.heardSound = false
                        if self.voice.mode == .pushToTalk { self.model.beginHearing() }
                    }

                case .level(let level):
                    // Only claim to be hearing something above the noise floor.
                    // A ring that reacts to a fan is a ring nobody believes.
                    if level > 0.18 {
                        self.heardSound = true
                        self.model.setPresence(.hearing, amplitude: level)
                    } else if self.model.presence == .hearing {
                        self.model.setPresence(.attentive, amplitude: 0)
                    }

                case .partial(let text):
                    self.heardSound = true
                    self.model.hear(partial: text)

                case .heard(let text):
                    if Self.earconOn { self.earcon.play() }
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

        // Hold a key to talk: the globe unless the menu says otherwise, see
        // `PushKey`.
        //
        // A modifier rather than a letter combination because it cannot
        // collide with what you are typing into the app underneath, and
        // holding it is a gesture rather than a shortcut to remember.
        // Nothing is captured until it goes down.
        //
        // Two monitors, because a global one sees only the events other apps
        // get. Click the pill and this app is the active one, and from then
        // on the key went nowhere; a release that landed here while the
        // press had been seen globally also left the microphone open.
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            if let down = PushKey.chosen.state(keyCode: event.keyCode, flags: event.modifierFlags) {
                Task { @MainActor in self?.globe(down: down) }
            } else if !PushKey.chosen.heldByFlags(event.modifierFlags) {
                Task { @MainActor in self?.talkKeyGoneByFlags() }
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            if let down = PushKey.chosen.state(keyCode: event.keyCode, flags: event.modifierFlags) {
                Task { @MainActor in self?.globe(down: down) }
            } else if !PushKey.chosen.heldByFlags(event.modifierFlags) {
                Task { @MainActor in self?.talkKeyGoneByFlags() }
            }
            return event
        }
    }

    /// A modifier event that was not the talk key, whose flags say the talk
    /// key is not held either.
    ///
    /// All that is left of reading the flag alone, kept for the one case that
    /// reading was protecting: a release for the talk key that never arrives,
    /// which would leave the microphone open with nothing to close it. It can
    /// only ever close a turn. It never opens one, and it never reaches
    /// `taps`, because a gesture is made of the talk key's own edges and
    /// everything else is at most evidence the key is no longer down. Feeding
    /// these events to `taps` is what made one hold read as the exit gesture
    /// 18 times in three hours on 2026-09-21.
    private func talkKeyGoneByFlags() {
        guard voice.mode == .pushToTalk, model.pill.phase == .hearing else { return }
        Self.keys.notice("voice.key failsafe close")
        taps.release()
        model.onEvent?(.talkKey(down: false))
        voice.endPush()
    }

    /// The talk key's state, from either monitor. Every flags change is
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
            // The glass is what he is talking to, so the key brings it up
            // rather than assuming it is already there. Held with the overlay
            // hidden, this opened the microphone behind a blank screen and the
            // only sign anything had happened was in the log. After the
            // double-tap check, so leaving still leaves.
            if let overlay, !overlay.isVisible { overlay.show() }
            // Up the socket before the microphone opens: the bridge stops
            // talking on this line, so the person is not talked over while
            // they speak.
            model.onEvent?(.talkKey(down: true))
            voice.beginPush()
        } else {
            taps.release()
            model.onEvent?(.talkKey(down: false))
            if !heardSound, model.pill.phase == .hearing {
                // Nothing reached the microphone: a press by accident. Not
                // the three-second wait for a final that never comes and
                // the red "Did not catch that" it ends in; the pill goes,
                // the band lingers a moment, and the next press works at
                // once because the turn is already closed.
                voice.dropPush()
                model.pressHeardNothing()
                return
            }
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
    static func flipped(_ point: NSPoint) -> CGPoint {
        guard let screen = OverlayWindow.active else { return point }
        return CGPoint(x: point.x, y: screen.frame.maxY - point.y)
    }

    private static func rect(from: CGPoint, to: CGPoint) -> CGRect {
        CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y),
            width: abs(to.x - from.x), height: abs(to.y - from.y))
    }

    // MARK: Hand control

    /// Whether hand control was last on, kept across launches.
    private static let handControlKey = "hud.handControl"

    /// Wire the two gestures to what they mean.
    ///
    /// Palm dismiss: the same semantic as the double-tap of the globe key.
    /// Point: the same region event the reticle sends.
    ///
    /// Both are redundant with a keyboard path that remains primary. The
    /// gestures have no discoverability, and nothing in the literature solves
    /// that (Kinect, Leap, Pixel 4 all died on it), so the keyboard is the
    /// thing people find and the camera is the thing people keep.
    private func setUpHands() {
        handTracker.onGesture = { [weak self] gesture in
            guard let self else { return }
            switch gesture {
            case .palmDismiss:
                self.leave()

            case .point(let unitPoint):
                guard let screen = OverlayWindow.active else { return }
                let frame = screen.frame
                // Unit coordinates (0-1, top-left origin) to screen points.
                let rect = CGRect(
                    x: unitPoint.x * frame.width,
                    y: unitPoint.y * frame.height,
                    width: 40, height: 40)
                self.model.mark(
                    id: "hand-point", rect: rect, label: "here", tone: nil, life: 4)
                self.model.onEvent?(.region(rect))
            }
        }
        if UserDefaults.standard.bool(forKey: Self.handControlKey) {
            handTracker.start()
        }
    }

    @objc private func toggleHandControl(_ sender: NSMenuItem) {
        let on = !handTracker.isRunning
        if on { handTracker.start() } else { handTracker.stop() }
        UserDefaults.standard.set(on, forKey: Self.handControlKey)
        sender.state = on ? .on : .off
    }

    /// Tell the field where the hand is, so the band can part round it. A
    /// pointer on another display is nowhere the band can reach.
    private func trackPointer() {
        let mouse = NSEvent.mouseLocation
        if !model.bubbles.isEmpty {
            model.hoverBubble(model.bubble(at: Self.flipped(mouse))?.id)
        }
        guard let screen = OverlayWindow.active, screen.frame.contains(mouse) else {
            model.point(at: nil, aspect: 1)
            return
        }
        let frame = screen.frame
        let unit = CGPoint(
            x: (mouse.x - frame.minX) / frame.width,
            y: (frame.maxY - mouse.y) / frame.height)
        model.point(at: unit, aspect: frame.width / max(frame.height, 1))
    }

    func updateInteractive() {
        // Refitting on every move is a no-op while the frame is right, and it
        // is what catches a display arrangement change the notification
        // below arrives late for.
        overlay?.fitToScreen()
        overlay?.updateInteractive(surfaces: model.frames, mouse: NSEvent.mouseLocation)
    }

    /// The glass has to follow the main display when the arrangement changes.
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
            ("Hold \(PushKey.chosen.title) to talk", .pushToTalk),
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

        // Which key is held. See `PushKey` for why there is a choice.
        let keyItem = NSMenuItem(title: "Talk key", action: nil, keyEquivalent: "")
        let keyMenu = NSMenu()
        for key in PushKey.allCases {
            let entry = NSMenuItem(title: key.label, action: #selector(setPushKey(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = key.rawValue
            entry.state = key == PushKey.chosen ? .on : .off
            keyMenu.addItem(entry)
        }
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)
        pushKeyMenu = keyMenu

        let soundItem = NSMenuItem(
            title: "Sound when heard", action: #selector(toggleEarcon(_:)), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = Self.earconOn ? .on : .off
        menu.addItem(soundItem)

        let handItem = NSMenuItem(
            title: "Hand control (camera)", action: #selector(toggleHandControl(_:)), keyEquivalent: "")
        handItem.target = self
        handItem.state = handTracker.isRunning ? .on : .off
        menu.addItem(handItem)
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

    @objc private func setPushKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let key = PushKey(rawValue: raw)
        else { return }
        UserDefaults.standard.set(raw, forKey: PushKey.defaultsKey)
        for item in pushKeyMenu?.items ?? [] {
            item.state = (item.representedObject as? String) == raw ? .on : .off
        }
        for item in voiceMenu?.items ?? []
        where (item.representedObject as? String) == VoiceListener.Mode.pushToTalk.rawValue {
            item.title = "Hold \(key.title) to talk"
        }
    }

    @objc private func toggleEarcon(_ sender: NSMenuItem) {
        let on = !Self.earconOn
        UserDefaults.standard.set(on, forKey: Self.earconKey)
        sender.state = on ? .on : .off
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
