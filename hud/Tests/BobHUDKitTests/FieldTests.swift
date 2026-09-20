import AppKit
import CoreGraphics
import MetalKit
import SwiftUI
import Testing

@testable import BobHUDKit

/// The field's inputs, owned by the test and read by the view.
@Observable
@MainActor
final class FieldHost {
    var presence: Presence = .dormant
    var amplitude: Double = 0
}

struct FieldHostView: View {
    let host: FieldHost
    var body: some View {
        PresenceField(presence: host.presence, amplitude: host.amplitude)
            .frame(width: 320, height: 200)
    }
}

/// Frames, collected from the renderer's trace on whatever thread it draws.
final class Frames: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [PresenceFieldRenderer.Trace] = []
    func add(_ frame: PresenceFieldRenderer.Trace) {
        lock.lock()
        frames.append(frame)
        lock.unlock()
    }
    var all: [PresenceFieldRenderer.Trace] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }
}

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

    @Test("the band never sits on one frame while it is up")
    @MainActor
    func staysAlive() async throws {
        // The real path, SwiftUI update to Metal frame, in a window nobody
        // can see: no alpha, no clicks, under the desktop. Every other test
        // of the field checks a number; this one checks what a person
        // watching the edge of the screen would have seen.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        let host = FieldHost()
        window.contentView = NSHostingView(rootView: FieldHostView(host: host))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        func metal(in view: NSView) -> MTKView? {
            if let m = view as? MTKView { return m }
            for child in view.subviews { if let m = metal(in: child) { return m } }
            return nil
        }
        let frames = Frames()
        PresenceFieldRenderer.trace = { frames.add($0) }
        defer { PresenceFieldRenderer.trace = nil }
        // Suspending rather than spinning the run loop, so that the main
        // actor keeps running: the field's own exit cleanup is a sleeping
        // task, and under `RunLoop.run(until:)` it never came back.
        func pump(_ seconds: Double) async {
            try? await Task.sleep(for: .seconds(seconds))
        }

        // A short errand: listen, think, act, say the result, hold, leave.
        host.presence = .attentive
        await pump(0.8)
        // MTKView's own clock never starts in a test process, even with the
        // app finished launching (tried 2026-09-20): it wants `NSApp.run`.
        // Driven by hand at sixty instead, skipping frames while the view is
        // parked, which is the one thing the clock does that matters here.
        let mtk = try #require(window.contentView.flatMap(metal(in:)), "no Metal view was made")
        let driver = Task { @MainActor in
            while !Task.isCancelled {
                if !mtk.isPaused { mtk.draw() }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
        defer { driver.cancel() }
        host.presence = .thinking
        await pump(0.5)
        host.presence = .acting
        await pump(0.8)
        for i in 0..<40 {
            host.amplitude = 0.3 + 0.3 * sin(Double(i) / 3)
            host.presence = .speaking
            await pump(0.03)
        }
        let doneAt = Date()
        host.presence = .done
        // The bridge holds `done` for ten seconds after the voice stops.
        await pump(8.0)
        let leftAt = Date()
        host.presence = .dormant
        await pump(4.0)

        let drawn = frames.all
        try #require(drawn.count > 20, "the hidden window never drew")
        // The timeline, for a failure to be read rather than guessed at.
        let t0 = drawn[0].at
        var last: PresenceFieldRenderer.Trace?
        for frame in drawn {
            if let last, frame.rate == last.rate, frame.paused == last.paused,
               frame.at.timeIntervalSince(last.at) < 0.5, abs(frame.drift - last.drift) < 0.05 {
                continue
            }
            print(String(
                format: "field %6.2fs rate=%d rest=%.3f drift=%.2f act=%.2f%@%@",
                frame.at.timeIntervalSince(t0), frame.rate, frame.rest, frame.drift, frame.act,
                frame.closing ? " closing" : "", frame.paused ? " parked" : ""))
            last = frame
        }
        print(String(format: "field done at %.2fs, left at %.2fs", doneAt.timeIntervalSince(t0), leftAt.timeIntervalSince(t0)))

        // While the band is up, nothing longer than a fifth of a second
        // passes between two frames: at that gap the liquid reads as
        // stopped. From the first frame to the exit's start.
        let up = drawn.filter { $0.at < leftAt }
        var longest = 0.0
        for (a, b) in zip(up, up.dropFirst()) {
            longest = max(longest, b.at.timeIntervalSince(a.at))
        }
        let held = up.filter { $0.at > doneAt }
        let still = held.last.map { leftAt.timeIntervalSince($0.at) } ?? 0
        #expect(longest < 0.2, "the band sat still for \(longest)s")
        #expect(still < 0.2, "the band sat on its last frame for \(still)s before leaving")

        // And once gone, it stops drawing: the battery half of the bargain.
        // The exit is 0.7s and the chases take about 2.3s more to settle to
        // nothing.
        let after = drawn.filter { $0.at > leftAt.addingTimeInterval(3.5) }
        #expect(after.isEmpty || after.allSatisfy { $0.paused }, "still drawing after leaving")
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
