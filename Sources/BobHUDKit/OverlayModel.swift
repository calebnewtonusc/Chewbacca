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
        (NSScreen.main?.visibleFrame.height ?? 800) - 36
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

    public init() {}

    public var isEmpty: Bool { surfaces.isEmpty && markers.isEmpty }

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
            sweepTask?.cancel()
            sweepTask = nil
            revision += 1

        case .close(let id):
            close(id)

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
    public func setPresence(_ next: Presence, amplitude: Double?) {
        presence = next
        if let amplitude { self.amplitude = amplitude }
        revision += 1

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
        surfaces = []
        heights = [:]
        current = "main"
        nextDepth = 0
        revision += 1
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
        surfaces.map { surface in
            let centre = origin(for: surface)
            let height = heights[surface.id] ?? 120
            return CGRect(
                x: centre.x - surface.width / 2,
                y: centre.y - height / 2,
                width: surface.width,
                height: height)
        }
    }

    /// Top-left origin for a surface, in the overlay's coordinate space.
    ///
    /// SwiftUI's `.position` places a view's centre, so this returns an offset
    /// applied after pinning to the origin, which keeps the arithmetic readable.
    public func origin(for surface: OverlaySurface) -> CGPoint {
        guard let screen = NSScreen.main else { return .zero }

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
