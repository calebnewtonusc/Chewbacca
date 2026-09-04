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
    /// The tallest this surface may draw. Always replaced with `ceiling` when
    /// the surface is opened; the literal is here only because a default in a
    /// nonisolated struct cannot touch `NSScreen`.
    public var maxHeight: CGFloat = 620

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
            && a.width == b.width && a.drag == b.drag && a.urgency == b.urgency
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

    /// Measured heights, reported by each card once laid out, so stacking uses
    /// real sizes rather than a guess.
    private var heights: [String: CGFloat] = [:]

    public init() {}

    public var isEmpty: Bool { surfaces.isEmpty }

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
        case .surface(let id, let region, let width, let urgency):
            current = id
            open(
                id,
                region: region ?? (urgency == .critical ? .center : .topRight),
                width: width.map { CGFloat($0) },
                urgency: urgency ?? .normal)

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

    /// A new connection clears the glass. Two agents drawing at once is a race
    /// with a visible symptom, so the last one in wins and starts from nothing.
    public func reset() {
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
        return open(id, region: .topRight, width: nil, urgency: .normal)
    }

    @discardableResult
    private func open(
        _ id: String, region: Region, width: CGFloat?, urgency: Urgency = .normal
    ) -> OverlaySurface {
        if let index = surfaces.firstIndex(where: { $0.id == id }) {
            // Moving or resizing an open surface mid-stream is a normal ask.
            var existing = surfaces[index]
            existing.region = region
            existing.urgency = urgency
            existing.maxHeight = OverlaySurface.ceiling
            if let width { existing.width = width }
            surfaces[index] = existing
            relayout()
            return existing
        }

        let store = SurfaceStore()
        store.onEvent = { [weak self] event in self?.onEvent?(event) }

        nextDepth += 1
        let surface = OverlaySurface(
            id: id, store: store, region: region,
            width: width ?? (urgency == .critical ? 420 : 380),
            slot: 0, depth: nextDepth, drag: .zero, urgency: urgency,
            maxHeight: OverlaySurface.ceiling)
        surfaces.append(surface)
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
