import AppKit
import Observation
import SwiftUI

/// One surface on the glass.
public struct OverlaySurface: Identifiable, Equatable {
    public let id: String
    public let store: SurfaceStore
    public var region: Region
    public var width: CGFloat
    /// Position within its region, so several in one corner stack downward.
    public var slot: Int
    public var depth: Int
    /// How far the person has dragged this surface from where it was placed.
    ///
    /// Kept separate from the region rather than folded into a coordinate, so a
    /// surface that gets moved still belongs to its corner: restacking, resizing
    /// and a display change all keep working, and the drag rides on top.
    public var drag: CGSize = .zero
    public var urgency: Urgency = .normal
    public var chrome: Chrome = .card
    /// The tallest this surface may draw. Always replaced with `ceiling` when
    /// the surface is opened; the literal is here only because a default in a
    /// nonisolated struct cannot touch `NSScreen`.
    public var maxHeight: CGFloat = 620
    /// When this panel takes itself down. Nil means it stays until closed,
    /// which is the default: a panel someone asked for should not vanish while
    /// they are reading it.
    public var expires: Date?

    /// The usable height of the display, less the margins the layout keeps.
    ///
    /// Read at open time rather than stored once, so plugging in a monitor or
    /// changing resolution is picked up by the next surface instead of leaving
    /// panels sized for a screen that is no longer there.
    @MainActor
    public static var ceiling: CGFloat {
        (OverlayWindow.active?.visibleFrame.height ?? 800) - 36
    }

    public static func == (a: OverlaySurface, b: OverlaySurface) -> Bool {
        a.id == b.id && a.region == b.region && a.slot == b.slot
            && a.width == b.width && a.drag == b.drag && a.urgency == b.urgency && a.chrome == b.chrome && a.expires == b.expires
    }
}

/// What is on the glass, and where.
///
/// The model owns placement so the view can stay declarative: an agent says
/// `@ people at=topRight` and this works out that the people surface is the
/// second thing in that corner and therefore sits below the first one.
@MainActor
@Observable
public final class OverlayModel {
    public private(set) var surfaces: [OverlaySurface] = []
    public private(set) var revision = 0
    /// Where the pointer is on the glass, in unit coordinates with a top-left
    /// origin, or nil when it is nowhere the field cares about. Kept for
    /// tests and for anything that asks; the field itself is told directly
    /// through `PresenceFieldRenderer.point`, and this is not observed at
    /// all: a pointer move must not re-evaluate a single SwiftUI body.
    @ObservationIgnored public private(set) var pointer: CGPoint?

    /// Where events from any surface go.
    public var onEvent: ((OutboundEvent) -> Void)?

    private var current: String = "main"
    private var nextDepth = 0
    /// Cancels the self-demote when the state changes before its patience runs
    /// out, which is the normal case.
    @ObservationIgnored private var patienceTask: Task<Void, Never>?
    /// Retires expired marks. Nil when nothing on screen can expire.
    @ObservationIgnored private var sweepTask: Task<Void, Never>?

    /// Measured heights, reported by each card once laid out, so stacking uses
    /// real sizes rather than a guess.
    private var heights: [String: CGFloat] = [:]

    /// The pill: the transcript, the breadcrumbs, the answer, and the bar.
    public private(set) var pill = PillState()
    /// How long a run takes on this machine, for the pill's fill.
    public private(set) var clock = RunClock.load()
    /// The pill's laid-out size, reported by the view, so its hit rectangle
    /// is the capsule that was actually drawn.
    public private(set) var pillSize: CGSize = .zero
    /// Where a cancel goes while the pill is still hearing: main.swift stops
    /// the microphone. A cancel while working goes up the socket instead.
    public var onPillCancel: ((PillState.Phase) -> Void)?
    /// Takes a failure or a stopped run off the pill after its hold.
    @ObservationIgnored private var pillHideTask: Task<Void, Never>?

    /// The conversation: every request and every written answer of the
    /// session, in order. The pill shows two lines of it at a time; the
    /// conversation panel shows all of it, and is where an answer can be
    /// copied from or a request typed. Asked for on 2026-09-19: "if click,
    /// have it expand into its own chat window so a user can copy and
    /// paste information or type their own requests if they dont want to
    /// speak".
    public private(set) var turns: [ChatTurn] = []
    /// Whether the conversation panel is up. The pill hides while it is.
    public private(set) var chatOpen = false
    /// How many times it has opened. The panel's window is built once and
    /// shown many times, so this is what its entrance animates on.
    public private(set) var chatOpenings = 0
    /// What main.swift does when the panel opens or closes: the panel is a
    /// window of its own, because a text field has to be able to take key
    /// and the glass must never.
    public var onChatOpen: (() -> Void)?
    public var onChatClose: (() -> Void)?
    private var nextTurn = 0

    public init() {}

    /// Includes the pill, so Escape can reach a run with nothing drawn yet.
    public var isEmpty: Bool {
        surfaces.isEmpty && markers.isEmpty && pill.phase == .hidden
    }

    /// True when something on the glass outranks the person having hidden it.
    ///
    /// Jarvis is told to stop reporting the power level and still speaks at two
    /// percent. This is that: a dismissed HUD stays dismissed for everything
    /// except the one thing that genuinely cannot wait.
    public var hasBreakthrough: Bool {
        surfaces.contains { $0.urgency.breaksThrough }
    }

    public func apply(_ op: Op) {
        switch op {
        case .surface(let id, let region, let width, let urgency, let chrome, let life):
            current = id
            open(
                id, region: region, width: width.map { CGFloat($0) },
                urgency: urgency, chrome: chrome, life: life)

        case .presence(let state, let amplitude):
            setPresence(state, amplitude: amplitude)

        case .mark(let id, let rect, let label, let tone, let life):
            mark(id: id, rect: rect, label: label, tone: tone, life: life)

        case .unmark(let id):
            if id.isEmpty {
                markers = []
            } else {
                markers.removeAll { $0.id == id }
            }
            // The sweep is deliberately *not* cancelled here.
            //
            // It used to be, and that meant taking down one marker stopped every
            // other marker and every surface with a lifetime from ever expiring.
            // The sweep already stops itself when nothing left can expire, which
            // is the only condition under which stopping it is correct.
            revision += 1

        case .close(let id):
            if id.isEmpty { reset() } else { close(id) }

        case .say(let text):
            say(text)

        case .step(let text):
            step(text)

        case .write(let text, let done):
            write(text, done: done)

        case .queued(let count):
            queued(count)

        default:
            surface(current).store.apply([op])
            revision += 1
        }
    }

    public func warn(_ message: String) {
        surfaces.first { $0.id == current }?.store.warn(message)
    }

    /// Take everything off the glass.
    ///
    /// Only ever called on an explicit gesture: Escape, or "Clear everything"
    /// in the menu. Connecting does not do this, because a surface has to
    /// outlive the connection that drew it for anything to be able to change it
    /// later.
    /// Marks drawn on the screen itself, newest last.
    public private(set) var markers: [Marker] = []

    /// The most marks the layer will hold at once.
    ///
    /// Twelve, the same cap the spec puts on the annotation layer and for a
    /// sharper reason than it puts on panels: past a dozen outlines a screen is
    /// not annotated, it is hatched, and nothing stands out because everything
    /// does.
    public static let maxMarkers = 12

    /// What the assistant is doing, and how loud the person is talking.
    public private(set) var presence: Presence = .dormant
    public private(set) var amplitude: Double = 0

    /// The most simultaneous surfaces the glass will hold.
    ///
    /// Twelve, from the annotation-layer spec, and it is a real limit rather
    /// than a guideline: past about a dozen elements a heads-up display stops
    /// being glanceable and becomes a second screen to read. When a thirteenth
    /// arrives the oldest goes, because the newest is the one that was just
    /// asked for.
    public static let maxSurfaces = 12

    /// Set the ring, and start the clock on states that claim progress.
    ///
    /// Presence drives every phase change on the pill too, so there is no
    /// separate "start work" verb: the bridge already says `p thinking`,
    /// `p done` and `p failed` at exactly the moments the pill needs.
    public func setPresence(_ next: Presence, amplitude: Double?) {
        presence = next
        if let amplitude { self.amplitude = amplitude }
        revision += 1

        switch next {
        case .thinking, .acting:
            // The bridge pulses `p thinking` every two seconds while a run is
            // on. While the key is held that pulse must not take the transcript
            // off the pill mid-sentence, so a hearing turn holds its phase and
            // the run picks the pill back up when the turn ends.
            if pill.phase != .working && pill.phase != .hearing { pill.phase = .working }
            // Set once, cleared only when the run ends. A press of the key in
            // the middle of a 70s run flips the phase to hearing, and the
            // next pulse re-enters working; resetting here would send the bar
            // and the counter back to zero on camera.
            if pill.startedAt == nil {
                pill.startedAt = Date()
                pill.saying = ""
            }

        case .done:
            if let start = pill.startedAt {
                clock.record(Date().timeIntervalSince(start))
                clock.save()
            }
            // `p done` with nothing running and nothing to say would put an
            // empty capsule on screen for the length of the bridge's hold.
            if pill.phase != .hidden || !pill.saying.isEmpty {
                pill.phase = .saying
            }
            pill.startedAt = nil
            // A bridge that never wrote the answer (an older one, or a
            // one-line reply) still said it: the pill's line is the answer.
            settleAnswer(fallback: pill.saying)

        case .failed:
            pill.phase = .failed
            pill.startedAt = nil
            if pill.saying.isEmpty { pill.saying = PillState.unfinished }
            settleAnswer(fallback: pill.saying)

        case .attentive, .dormant:
            // Only the phases that have said their piece go away. main.swift
            // sends `attentive` on every quiet audio buffer, which is the first
            // few hundred milliseconds of every press, so an empty hearing
            // turn must survive it: `cancelRun()` or `fail(_:hold:)` take
            // that one down explicitly.
            if pill.phase == .saying || pill.phase == .failed {
                pill = PillState(queued: pill.queued)
            }

        case .hearing, .speaking, .attention:
            // Speaking leaves the pill where it is. The reply is already on
            // it as `saying`, or a breadcrumb is, while the run goes on: the
            // voice only moves the ring.
            break
        }
        pillHideTask?.cancel()

        patienceTask?.cancel()
        guard let patience = next.patience else { return }
        // An indefinite spinner is a lie. If nothing has changed the state by
        // the time its patience runs out, the ring stops claiming progress and
        // says so instead.
        patienceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: patience)
            guard !Task.isCancelled, let self, self.presence == next else { return }
            self.presence = .attention
            self.revision += 1
        }
    }

    /// Put a mark up, or refresh one that is already there.
    ///
    /// Refreshing rather than duplicating is what makes tracking possible: an
    /// agent watching something move re-sends the same id with a new rectangle
    /// and the mark follows, instead of leaving a trail of stale outlines.
    public func mark(
        id: String, rect: CGRect, label: String, tone: String?, life: Double?
    ) {
        // `life=0` pins it. Anything else, including an omitted value, expires.
        let expires: Date? = (life == 0)
            ? nil
            : Date().addingTimeInterval(life ?? Marker.defaultLife)
        let marker = Marker(id: id, rect: rect, label: label, tone: tone, expires: expires)

        if let index = markers.firstIndex(where: { $0.id == id }) {
            markers[index] = marker
        } else {
            markers.append(marker)
            if markers.count > Self.maxMarkers { markers.removeFirst() }
        }
        revision += 1
        startSweep()
    }

    /// Retire marks as they expire.
    ///
    /// One timer for the whole layer rather than one per mark: a dozen timers
    /// firing independently is a dozen redraws of the same view, and this runs
    /// on somebody's real machine while they work.
    private func startSweep() {
        guard sweepTask == nil else { return }
        sweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                let now = Date()
                let before = self.markers.count
                self.markers.removeAll { marker in
                    guard let expires = marker.expires else { return false }
                    return expires <= now
                }
                // Panels expire on the same sweep rather than a second timer.
                let surfacesBefore = self.surfaces.count
                self.surfaces.removeAll { surface in
                    guard let expires = surface.expires else { return false }
                    return expires <= now
                }
                if self.surfaces.count != surfacesBefore { self.relayout() }
                if self.markers.count != before { self.revision += 1 }
                if self.markers.allSatisfy({ $0.expires == nil })
                    && self.surfaces.allSatisfy({ $0.expires == nil }) {
                    self.sweepTask = nil
                    return
                }
            }
        }
    }

    public func reset() {
        markers = []
        sweepTask?.cancel()
        sweepTask = nil
        presence = .dormant
        patienceTask?.cancel()
        pill = PillState()
        pillHideTask?.cancel()
        pillHideTask = nil
        surfaces = []
        heights = [:]
        current = "main"
        nextDepth = 0
        // The conversation survives. Escape takes the glass back; it does
        // not forget what was said, because the bridge's session has not
        // forgotten either, and a panel that opens empty over a model that
        // remembers the last exchange is lying about one of them.
        // `clearChat` is the deliberate version.
        closeChat()
        revision += 1
    }

    // MARK: The conversation

    /// A request went up the socket, spoken or typed. It goes into the
    /// conversation at once with an empty answer after it, so the panel
    /// shows the question while the answer is still being written.
    public func asked(_ text: String, typed: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        turns.append(ChatTurn(id: take(), role: .person, text: trimmed, done: true, typed: typed))
        turns.append(ChatTurn(id: take(), role: .assistant, text: "", done: false, typed: typed))
        trimTurns()
        revision += 1
    }

    /// The answer so far, replacing what was there; `done` closes it. With
    /// no answer open (a `w` sent by hand, or after a stop), it opens one.
    public func write(_ text: String, done: Bool) {
        if let index = turns.lastIndex(where: { $0.role == .assistant && !$0.done }) {
            turns[index].text = text
            turns[index].done = done
            if done { turns[index].endedAt = Date() }
        } else {
            turns.append(ChatTurn(id: take(), role: .assistant, text: text, done: done, typed: false))
            trimTurns()
        }
        revision += 1
    }

    /// Close every open answer. One with nothing written takes `fallback`,
    /// which is the pill's last line: for a one-sentence reply that is the
    /// whole answer, and for a failure it is what went wrong.
    private func settleAnswer(fallback: String) {
        var changed = false
        for index in turns.indices where turns[index].role == .assistant && !turns[index].done {
            if turns[index].text.isEmpty { turns[index].text = fallback }
            turns[index].done = true
            turns[index].endedAt = Date()
            changed = true
        }
        if changed { revision += 1 }
    }

    /// The most turns kept. Two hundred: a long evening of asking, and far
    /// under what a `LazyVStack` minds. Guessed, never measured.
    public static let maxTurns = 200

    private func trimTurns() {
        if turns.count > Self.maxTurns {
            turns.removeFirst(turns.count - Self.maxTurns)
        }
    }

    private func take() -> Int {
        nextTurn += 1
        return nextTurn
    }

    public func openChat() {
        guard !chatOpen else { return }
        chatOpen = true
        chatOpenings += 1
        revision += 1
        onChatOpen?()
    }

    public func closeChat() {
        guard chatOpen else { return }
        chatOpen = false
        revision += 1
        onChatClose?()
    }

    public func toggleChat() {
        if chatOpen { closeChat() } else { openChat() }
    }

    /// Forget the conversation. The panel's own button, and "Clear
    /// everything" in the menu; nothing else.
    public func clearChat() {
        turns = []
        revision += 1
    }

    // MARK: The pill

    /// The key went down. Live words follow through `hear(partial:)`.
    public func beginHearing() {
        pill.phase = .hearing
        pill.heard = ""
        pillHideTask?.cancel()
        revision += 1
    }

    /// The recogniser's current guess at the sentence so far.
    public func hear(partial: String) {
        pill.heard = partial
        revision += 1
    }

    /// The sentence the person actually said. The pill shows it until presence
    /// says thinking, so the caller owns any grace window before that.
    public func heard(_ text: String) {
        pill.phase = .heard
        pill.heard = text
        revision += 1
    }

    /// The agent's line: a breadcrumb while working, the answer after. Does
    /// not re-arm the ring's patience; the bridge pulses `p` while events flow
    /// and that is what keeps the ring honest.
    public func say(_ text: String) {
        pill.saying = text
        pill.step = false
        revision += 1
    }

    /// A tool call, in words. On the pill, and on the open answer's list of
    /// steps, so the panel can say what was done once the answer is in.
    public func step(_ text: String) {
        pill.saying = text
        pill.step = true
        if let index = turns.lastIndex(where: { $0.role == .assistant && !$0.done }),
           turns[index].steps.last != text {
            turns[index].steps.append(text)
        }
        revision += 1
    }

    public func queued(_ count: Int) {
        pill.queued = max(0, count)
        revision += 1
    }

    /// Put a failure on the pill and take it down again after `hold` seconds,
    /// unless something else has moved the pill on by then.
    public func fail(_ message: String, hold: TimeInterval) {
        pill.phase = .failed
        pill.saying = message
        pill.startedAt = nil
        settleAnswer(fallback: message)
        // `p failed` may have closed the answer with the placeholder a
        // moment ago; the message is the better version of it.
        if let index = turns.lastIndex(where: { $0.role == .assistant }),
           turns[index].text.isEmpty || turns[index].text == PillState.unfinished {
            turns[index].text = message
        }
        revision += 1
        pillHideTask?.cancel()
        pillHideTask = hide(after: hold, ifStill: .failed)
    }

    /// The X on the pill, or Escape.
    ///
    /// What it means depends on where the request is. Still being heard: the
    /// microphone stops and the words go. In flight: the bridge is told to
    /// stop, as the same `e stop run` line any control would send, and what
    /// has already been drawn stays. Finished: the pill goes away.
    public func cancelRun() {
        switch pill.phase {
        case .hearing, .heard:
            onPillCancel?(pill.phase)
            pill = PillState(queued: pill.queued)
            pillHideTask?.cancel()

        case .working:
            onEvent?(.action(name: "stop", component: "run", payload: [:]))
            pill.phase = .saying
            pill.saying = "Stopped. What was drawn stays."
            pill.startedAt = nil
            settleAnswer(fallback: "Stopped.")
            // The bridge answers a stop with `p failed` and its own hold. If
            // nothing is listening to answer, do not sit here forever. Three
            // seconds is guessed, never measured.
            pillHideTask?.cancel()
            pillHideTask = hide(after: 3, ifStill: .saying)

        case .saying, .failed:
            pill = PillState(queued: pill.queued)
            pillHideTask?.cancel()

        case .hidden:
            break
        }
        revision += 1
    }

    private func hide(after seconds: TimeInterval, ifStill phase: PillState.Phase) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.pill.phase == phase else { return }
            self.pill = PillState(queued: self.pill.queued)
            self.revision += 1
        }
    }

    /// Beyond this distance from the nearest edge, in screen heights, the
    /// pointer is nobody's business: the deepest band (0.075) plus a 30pt
    /// parting on the shortest display this runs on (982pt), rounded up.
    public static let pointerReach: CGFloat = 0.12

    /// The mouse moved. `unit` is where, in unit coordinates with a top-left
    /// origin; `aspect` is the display's width over its height, so the
    /// distance to a side edge can be measured in the same screen heights
    /// the shader uses. Quantised to a four-thousandth of the screen, under
    /// a point on any display here, so a pointer that has not really moved
    /// does not wake the field; nil across the middle of the display, where
    /// the field draws nothing.
    public func point(at unit: CGPoint?, aspect: CGFloat) {
        let next: CGPoint? = unit.flatMap { p in
            let near = min(p.x * aspect, (1 - p.x) * aspect, p.y, 1 - p.y)
            guard near < Self.pointerReach else { return nil }
            return CGPoint(x: (p.x * 4000).rounded() / 4000, y: (p.y * 4000).rounded() / 4000)
        }
        guard next != pointer else { return }
        pointer = next
        PresenceFieldRenderer.point(at: next)
    }

    public func report(pillSize: CGSize) {
        guard abs(pillSize.width - self.pillSize.width) > 1
            || abs(pillSize.height - self.pillSize.height) > 1
        else { return }
        self.pillSize = pillSize
    }

    /// The pill's rectangle in the overlay's coordinate space, or nil while
    /// hidden. Without this the X on it draws and cannot be clicked, because
    /// the window only accepts the mouse over a rectangle it knows about.
    public var pillFrame: CGRect? {
        guard pill.phase != .hidden, pillSize != .zero,
              let screen = OverlayWindow.active
        else { return nil }
        let full = screen.frame
        let usable = screen.visibleFrame
        let bottomInset = usable.minY - full.minY
        return CGRect(
            x: (full.width - pillSize.width) / 2,
            y: full.height - bottomInset - PillView.pillLift - pillSize.height,
            width: pillSize.width,
            height: pillSize.height)
    }

    public func close(_ id: String) {
        surfaces.removeAll { $0.id == id }
        heights.removeValue(forKey: id)
        if current == id { current = surfaces.last?.id ?? "main" }
        relayout()
    }

    /// Move a surface by hand. Dragging outranks placement: an agent said where
    /// to put it, the person said where they want it, and the person wins.
    public func move(_ id: String, by translation: CGSize) {
        guard let index = surfaces.firstIndex(where: { $0.id == id }) else { return }
        surfaces[index].drag = translation
        revision += 1
    }

    /// Bring a surface to the front, so the one being touched is on top.
    public func raise(_ id: String) {
        guard let index = surfaces.firstIndex(where: { $0.id == id }) else { return }
        nextDepth += 1
        surfaces[index].depth = nextDepth
        revision += 1
    }

    public func report(height: CGFloat, for id: String) {
        guard abs((heights[id] ?? 0) - height) > 1 else { return }
        heights[id] = height
        relayout()
    }

    @discardableResult
    private func surface(_ id: String) -> OverlaySurface {
        if let existing = surfaces.first(where: { $0.id == id }) { return existing }
        return open(id, region: nil, width: nil, urgency: nil, chrome: nil)
    }

    /// Open a surface, or re-address one that is already on the glass.
    ///
    /// Everything is optional and an omitted field is *kept*, not reset. This is
    /// what lets a follow-up be a follow-up: `@ notes` on its own means "I am
    /// talking about that panel again", and it would be a strange reading of
    /// that to move the panel back to the top right and put its chrome back to
    /// a card. Only a new surface takes defaults.
    @discardableResult
    private func open(
        _ id: String, region: Region?, width: CGFloat?,
        urgency: Urgency?, chrome: Chrome?, life: Double? = nil
    ) -> OverlaySurface {
        if let index = surfaces.firstIndex(where: { $0.id == id }) {
            // Moving or resizing an open surface mid-stream is a normal ask.
            var existing = surfaces[index]
            if let region { existing.region = region }
            if let urgency { existing.urgency = urgency }
            if let chrome { existing.chrome = chrome }
            if let life { existing.expires = life == 0 ? nil : Date().addingTimeInterval(life) }
            existing.maxHeight = OverlaySurface.ceiling
            if let width { existing.width = width }
            surfaces[index] = existing
            if existing.expires != nil { startSweep() }
            relayout()
            return existing
        }

        let store = SurfaceStore()
        store.onEvent = { [weak self] event in self?.onEvent?(event) }

        nextDepth += 1
        let surface = OverlaySurface(
            id: id, store: store,
            region: region ?? (urgency == .critical ? .center : .topRight),
            width: width ?? (urgency == .critical ? 420 : 380),
            slot: 0, depth: nextDepth, drag: .zero,
            urgency: urgency ?? .normal, chrome: chrome ?? .card,
            maxHeight: OverlaySurface.ceiling,
            expires: life.map { $0 == 0 ? .distantFuture : Date().addingTimeInterval($0) })
        surfaces.append(surface)
        if surface.expires != nil { startSweep() }
        // Drop the oldest rather than refusing the newest: the one just asked
        // for is the one the person is looking for.
        if surfaces.count > Self.maxSurfaces {
            let evicted = surfaces.removeFirst()
            heights[evicted.id] = nil
        }
        relayout()
        return surface
    }

    private func relayout() {
        var used: [Region: Int] = [:]
        for index in surfaces.indices {
            let region = surfaces[index].region
            surfaces[index].slot = used[region, default: 0]
            used[region] = surfaces[index].slot + 1
        }
        revision += 1
    }

    /// Every surface's rectangle, in the overlay's own coordinate space.
    ///
    /// Needed because the window has to know whether the pointer is over
    /// something before it decides to accept a mouse event at all.
    public var frames: [CGRect] {
        var all = surfaces.map { surface in
            let centre = origin(for: surface)
            let height = heights[surface.id] ?? 120
            return CGRect(
                x: centre.x - surface.width / 2,
                y: centre.y - height / 2,
                width: surface.width,
                height: height)
        }
        if let pillFrame { all.append(pillFrame) }
        return all
    }

    /// Top-left origin for a surface, in the overlay's coordinate space.
    ///
    /// SwiftUI's `.position` places a view's centre, so this returns an offset
    /// applied after pinning to the origin, which keeps the arithmetic readable.
    public func origin(for surface: OverlaySurface) -> CGPoint {
        guard let screen = OverlayWindow.active else { return .zero }

        // The window covers the whole display, menu bar and Dock included, but
        // nothing should be *placed* under either of them. `visibleFrame` is the
        // usable area, and the difference between the two frames is the inset.
        // Getting this wrong is what pushed the bottom surfaces off the screen.
        let full = screen.frame
        let usable = screen.visibleFrame
        let topInset = full.maxY - usable.maxY
        let bottomInset = usable.minY - full.minY
        let leftInset = usable.minX - full.minX
        let rightInset = full.maxX - usable.maxX

        let margin: CGFloat = 18
        let gap: CGFloat = 12
        let anchor = surface.region.anchor

        // Sum the heights of everything already in this region, so a stack is
        // spaced by what is actually there rather than by a fixed guess.
        var above: CGFloat = 0
        for other in surfaces
        where other.region == surface.region && other.slot < surface.slot {
            above += (heights[other.id] ?? 120) + gap
        }

        let width = surface.width
        let height = heights[surface.id] ?? 120

        let minX = leftInset + margin
        let maxX = full.width - rightInset - margin - width
        let minY = topInset + margin
        let maxY = full.height - bottomInset - margin - height

        // SwiftUI's origin is top left with y increasing downward, so an anchor
        // of 1.0 (the top of the screen) maps to the smaller y.
        let x = minX + max(0, maxX - minX) * anchor.x
        var y = minY + max(0, maxY - minY) * (1 - anchor.y) + above

        // A tall stack must not run off the bottom of the usable area.
        y = min(y, maxY)

        // `.position` places a centre, so hand back the centre of the frame,
        // plus wherever the person has dragged it.
        return CGPoint(
            x: x + width / 2 + surface.drag.width,
            y: y + height / 2 + surface.drag.height)
    }
}
