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
        // Thirty points on a 982pt display.
        let reach: Float = 30 / 982
        // Over the band at the left edge, a third of the way down.
        #expect(PresenceFieldRenderer.parting(
            pointer: CGPoint(x: 0.01, y: 0.33), aspect: 1.54, rest: rest, reach: reach) == 1)
        // Dead centre of the display.
        #expect(PresenceFieldRenderer.parting(
            pointer: CGPoint(x: 0.5, y: 0.5), aspect: 1.54, rest: rest, reach: reach) == 0)
        // Nothing to part for.
        #expect(PresenceFieldRenderer.parting(
            pointer: nil, aspect: 1.54, rest: rest, reach: reach) == 0)
        // Halfway between the band and the reach is somewhere in between,
        // which is what lets it start moving before the cursor arrives.
        let between = PresenceFieldRenderer.parting(
            pointer: CGPoint(x: 0.5, y: Double(rest + reach / 2)), aspect: 1.54, rest: rest,
            reach: reach)
        #expect(between > 0.3 && between < 0.7)
    }

    @Test("entering a still state keeps the clock live until it has eased in")
    func stillStatePaces() {
        // `done` says one frame a second. Asking the view for that before
        // the ease has run stalls it for the whole second: the band froze
        // mid-motion on every finished task.
        #expect(PresenceFieldRenderer.rate(
            for: Presence.done.field, closing: false, settled: false, parting: false) == 30)
        #expect(PresenceFieldRenderer.rate(
            for: Presence.dormant.field, closing: false, settled: false, parting: false) == 30)
    }

    @Test("a live state that has settled runs at its own pace")
    func settledPaces() {
        #expect(PresenceFieldRenderer.rate(
            for: Presence.attentive.field, closing: false, settled: true, parting: false) == 20)
        #expect(PresenceFieldRenderer.rate(
            for: Presence.hearing.field, closing: false, settled: true, parting: false) == 60)
    }

    @Test("the exit and the parting want sixty whatever the state says")
    func fastPaths() {
        #expect(PresenceFieldRenderer.rate(
            for: Presence.dormant.field, closing: true, settled: false, parting: false) == 60)
        #expect(PresenceFieldRenderer.rate(
            for: Presence.attentive.field, closing: false, settled: true, parting: true) == 60)
    }

    @Test("a frame after a long gap eases as one frame, not across the gap")
    func wakeEases() {
        // Seven seconds parked in `done`, then something changed.
        #expect(PresenceFieldRenderer.easeInterval(gap: 7.0, rate: 30) == 1.0 / 30)
        // A stall at one frame a second is a wake too, not a slow frame.
        #expect(PresenceFieldRenderer.easeInterval(gap: 1.0, rate: 1) == 1.0 / 30)
        // A real frame at sixty is its own length.
        #expect(PresenceFieldRenderer.easeInterval(gap: 0.017, rate: 60) == 0.017)
        // The first frame ever has no clock and snaps, as before.
        #expect(PresenceFieldRenderer.easeInterval(gap: 0, rate: 60) == 0)
    }

    @Test("a re-render that changed nothing leaves the clock alone")
    @MainActor
    func unchangedFrame() {
        let renderer = PresenceFieldRenderer()
        let done = PresenceFrame(
            style: Presence.done.field, awokeAt: .now, closingAt: nil, heard: 0, alpha: 1)
        // The first sight of `done` starts the clock, at a live rate.
        #expect(renderer.receive(frame: done, paused: true) == 30)
        // The pill hiding, a transcript line landing: the overlay re-renders
        // and the field is handed the same frame again. Touching the clock
        // here restarts it, which is a stall.
        #expect(renderer.receive(frame: done, paused: true) == nil)
        // Going away is a change, and it runs at sixty.
        let leaving = PresenceFrame(
            style: Presence.dormant.field, awokeAt: done.awokeAt, closingAt: .now, heard: 0,
            alpha: 1)
        #expect(renderer.receive(frame: leaving, paused: false) == 60)
    }

    @Test("a pointer that has not really moved does not wake the model")
    @MainActor
    func quantised() {
        let model = OverlayModel()
        // Near the left edge, within reach of the band.
        model.point(at: CGPoint(x: 0.05004, y: 0.5), aspect: 1.5)
        let first = model.pointer
        #expect(first != nil)
        model.point(at: CGPoint(x: 0.05006, y: 0.5), aspect: 1.5)
        #expect(model.pointer == first)
        // The middle of the display is nobody's business.
        model.point(at: CGPoint(x: 0.5, y: 0.5), aspect: 1.5)
        #expect(model.pointer == nil)
    }
}
