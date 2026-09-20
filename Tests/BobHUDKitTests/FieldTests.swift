import CoreGraphics
import Testing

@testable import BobHUDKit

/// The presence field's easing, which is the difference between a state
/// change and a jump. Everything the shader is told now follows its target
/// on a clock, and these are the properties that make that safe to park.
@Suite("Presence field")
struct FieldTests {
    @Test("a state change eases in rather than landing in one frame")
    func eases() {
        var depth = Chase(shown: 0.039, tau: 0.35)
        depth.step(toward: 0.018, dt: 1.0 / 30)
        // One frame at 30fps moves about nine percent of the way.
        #expect(depth.shown < 0.039)
        #expect(depth.shown > 0.030)
    }

    @Test("it settles, so the view can park")
    func settles() {
        var depth = Chase(shown: 0.039, tau: 0.35)
        for _ in 0..<90 { depth.step(toward: 0.018, dt: 1.0 / 30) }
        #expect(depth.settled(at: 0.018))
    }

    @Test("a first frame with no clock snaps rather than easing from nowhere")
    func snaps() {
        var depth = Chase(shown: 0, tau: 0.35)
        depth.step(toward: 0.049, dt: 0)
        #expect(depth.shown == 0.049)
    }

    @Test("the band parts for a pointer in it and not for one across the room")
    func parting() {
        let rest: Float = 0.039
        // Over the band at the left edge, a third of the way down.
        #expect(PresenceFieldRenderer.parting(
            pointer: CGPoint(x: 0.01, y: 0.33), aspect: 1.54, rest: rest) == 1)
        // Dead centre of the display.
        #expect(PresenceFieldRenderer.parting(
            pointer: CGPoint(x: 0.5, y: 0.5), aspect: 1.54, rest: rest) == 0)
        // Nothing to part for.
        #expect(PresenceFieldRenderer.parting(pointer: nil, aspect: 1.54, rest: rest) == 0)
        // Halfway between the band and one radius out is somewhere in between,
        // which is what lets it start moving before the cursor arrives.
        let between = PresenceFieldRenderer.parting(
            pointer: CGPoint(x: 0.5, y: Double(rest) + 0.02 + 0.07), aspect: 1.54, rest: rest)
        #expect(between > 0.3 && between < 0.7)
    }

    @Test("a pointer that has not really moved does not wake the model")
    @MainActor
    func quantised() {
        let model = OverlayModel()
        model.point(at: CGPoint(x: 0.10004, y: 0.5), aspect: 1.5)
        let first = model.pointer
        #expect(first != nil)
        model.point(at: CGPoint(x: 0.10006, y: 0.5), aspect: 1.5)
        #expect(model.pointer == first)
        // The middle of the display is nobody's business.
        model.point(at: CGPoint(x: 0.5, y: 0.5), aspect: 1.5)
        #expect(model.pointer == nil)
    }
}
