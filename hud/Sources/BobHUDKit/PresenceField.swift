import MetalKit
import SwiftUI

/// What the shader is told about a state, and how often to redraw for it.
///
/// One row per named state, in `Presence.field` below. The shader has no idea
/// there are seven states: it takes three numbers and a frame rate, so adding
/// a state is a row in that table rather than a branch in Metal.
struct PresenceFieldStyle: Equatable {
    /// How deep the pool sits at rest, measured from the screen edge inward.
    ///
    /// Not the same quantity these numbers used to hold. The shader's band
    /// used to be measured from zero and the screen edge sat at 0.200 of it,
    /// so most of every value here was spent getting to the edge and only the
    /// remainder was visible. Scaling those old numbers down on 2026-09-19
    /// took five of the seven states below 0.200, which does not draw a
    /// thinner band: it draws nothing along the four straight edges and
    /// leaves the corners, where the silhouette dips, as four smudges. Now
    /// this is the visible depth directly, so halving it halves the band.
    var rest: Double
    /// How fast the contour field travels round the edge.
    var drift: Double
    /// What the body is multiplied by, and how much of it to take. rgb then
    /// amount, so `FieldTint.steel` at amount zero leaves the palette alone.
    var tint: SIMD4<Float>
    /// How many times a second the whole layer breathes, or 0 for a state
    /// that holds still. Distinct from the two-beat pulse in `PresenceFrame`:
    /// that one fires twice and stops, this one runs while the state is up.
    var pulse: Double
    /// Redraw rate while this state is up and settled. Never handed to the
    /// view mid-transition, and a still state's one frame a second is never
    /// handed to it at all: the view parks instead. See
    /// `PresenceFieldRenderer.rate`.
    var fps: Int
    /// False means one frame and then stop. A layer that redraws forever is a
    /// battery bug, which is the objection `PresenceRing` raises about itself.
    var animating: Bool
}

/// The three readings colour is spent on, and there are only three.
///
/// Every other channel in this layer is weak: thickness needs a side by side
/// comparison to read at all, and rate needs you to already be watching.
/// Colour is the one that works in peripheral vision, so it carries the
/// distinction that matters most, which is what the assistant is doing to the
/// machine right now.
enum FieldTint {
    /// Listening, waiting, idle, asking. The steel palette with nothing added,
    /// which is white by construction: every constant in the shader sits
    /// within a few percent of neutral.
    static let steel = SIMD4<Float>(1, 1, 1, 0)
    /// Working. Goes with a pulse, because a task in flight is the one thing
    /// here that is still changing and it should read that way.
    ///
    /// The amount is 0.70 and not 1: at full strength the band stops being a
    /// steel edge that has gone green and becomes a green edge, and the thing
    /// this layer is meant to look like is an instrument, not a status light.
    /// Between the amount and the pulse the hue swings from about a quarter to
    /// six tenths, which is a clear band with green moving through it.
    static let green = SIMD4<Float>(0.28, 1.45, 0.55, 0.60)
    /// Finished, and holding. Darker than `green` and not pulsing, so the two
    /// are not one state in two brightnesses: done is news that stops. Its
    /// amount is higher because nothing is moving to carry it.
    static let deepGreen = SIMD4<Float>(0.14, 0.62, 0.30, 0.75)
    /// Failed. The only tint taken at full strength, because it is the only
    /// one where being unmistakable beats being quiet.
    static let red = SIMD4<Float>(1.15, 0.38, 0.30, 1)
}

extension Presence {
    /// The whole mapping from named state to field.
    ///
    /// Each state has to be identifiable in peripheral vision without being
    /// looked at, so they are separated on rate first and thickness second.
    /// Reading the word takes a glance; noticing that the edge started moving
    /// does not.
    ///
    /// Every `rest` below is four fifths of what it was. The first version of
    /// this table drawn as visible depth was reviewed on screen on 2026-09-19
    /// and the ask was "decrease the frame we have now slightly, its a bit
    /// too big", so the whole table moved together and the ratios between
    /// states are untouched: attentive 0.049 to 0.039, hearing 0.022 to
    /// 0.018, thinking 0.029 to 0.023, acting 0.061 to 0.049, done 0.038 to
    /// 0.030, attention 0.094 to 0.075, failed 0.072 to 0.058. Dormant is
    /// still zero, because zero is the one value that draws nothing.
    var field: PresenceFieldStyle {
        switch self {
        case .dormant:
            // Nothing. Not a thin band: the assistant is not there, and a
            // depth of zero is the one value the shader draws no pixels for.
            return .init(
                rest: 0, drift: 0, tint: FieldTint.steel, pulse: 0, fps: 1, animating: false)
        case .attentive:
            return .init(
                rest: 0.039, drift: 0.5, tint: FieldTint.steel, pulse: 0, fps: 20,
                animating: true)
        case .hearing, .speaking:
            // The two states driven from outside. `rest` here is a floor and
            // the voice adds to it, so 60fps is not decoration: it is the rate
            // the amplitude arrives at. Its own voice draws the same as the
            // person's on purpose; see `Presence.speaking`.
            //
            // Drift was 0.35, a slow current under a band whose thickness
            // did the talking. Asked for on 2026-09-19: "speed up the
            // waviness when a user is talking and when the engine is
            // responding". 2.4 is most of the way to thinking's 3.2, so the
            // flow reads as fast while the two stay apart: a voice is thick
            // and moving with the sound, thinking is thin and sprinting.
            return .init(
                rest: 0.018, drift: 2.4, tint: FieldTint.steel, pulse: 0, fps: 60,
                animating: true)
        case .thinking:
            // Thin and fast. Work reads as travel round the edge rather than
            // as weight on it, and it is still white: nothing has been done to
            // the machine yet.
            return .init(
                rest: 0.023, drift: 3.2, tint: FieldTint.steel, pulse: 0, fps: 30,
                animating: true)
        case .acting:
            // Green and breathing, and the only state that breathes on its own
            // clock. Something is being done to the person's machine right now
            // and that is the one thing in this vocabulary worth a colour they
            // cannot miss.
            return .init(
                rest: 0.049, drift: 1.1, tint: FieldTint.green, pulse: 0.8, fps: 30,
                animating: true)
        case .done:
            // Darker green, still, one frame. It is the same hue as `acting`
            // on purpose, because it is the end of that same errand, and it is
            // darker and stops moving because there is nothing left to wait
            // for.
            return .init(
                rest: 0.030, drift: 0.1, tint: FieldTint.deepGreen, pulse: 0, fps: 1,
                animating: false)
        case .attention:
            // The thickest, because this is the one that has to be noticed. It
            // stays white: green and red are spoken for, and a third hue here
            // would make the palette decoration again.
            return .init(
                rest: 0.075, drift: 0.9, tint: FieldTint.steel, pulse: 0, fps: 30,
                animating: true)
        case .failed:
            return .init(
                rest: 0.058, drift: 0.3, tint: FieldTint.red, pulse: 0, fps: 20,
                animating: true)
        }
    }
}

/// What the renderer is drawing this instant.
struct PresenceFrame: Equatable {
    var style: PresenceFieldStyle
    /// When it came up out of `dormant`, or nil while it is down. A date and
    /// not an elapsed time: the view redraws on its own clock and this struct
    /// only changes when the state does, so a number here would sit still for
    /// the whole 0.70s of a departure and freeze it at its first frame.
    var awokeAt: Date?
    /// When it started going away, or nil for "not going anywhere".
    var closingAt: Date?
    /// Thickness on top of `style.rest`, from the voice. Only in `hearing`.
    var heard: Double
    /// Scales the whole layer's alpha, for the two states that pulse.
    var alpha: Double
}

/// One number that follows another instead of jumping to it.
///
/// Every state change used to land in one frame: the band went from 0.039
/// deep to 0.018 the instant the key went down, the contour field jumped
/// when `drift` went from 0.5 to 3.2, and `acting` started its breath at
/// whatever phase the clock happened to be on. Seen on 2026-09-19 as "its
/// not clean and fluid transitioning". Exponential off real elapsed time
/// rather than a per-frame constant, because the live rates run from 20 to
/// 60fps and a fixed step per frame would take three times longer in one
/// state than in another.
struct Chase: Equatable {
    var shown: Float
    /// Time constant. 0.30s puts it about 95% of the way there in a second.
    var tau: Float

    mutating func step(toward target: Float, dt: Double) {
        guard dt > 0, tau > 0 else {
            shown = target
            return
        }
        shown += (target - shown) * Float(1 - exp(-dt / Double(tau)))
    }

    /// Close enough to stop redrawing for. A thousandth is under one level
    /// out of 255 on every channel this feeds.
    func settled(at target: Float) -> Bool {
        abs(shown - target) < 0.001
    }
}

/// The layer itself.
///
/// It sits behind the marks and the surfaces and draws nothing at all across
/// the middle of the display. That is not a nicety: `OverlayView` notes that
/// any background on this glass, at any opacity, tints the whole screen, so the
/// shader returns an empty alpha everywhere except the edge.
@MainActor
struct PresenceField: View {
    let presence: Presence
    /// 0 to 1, only read in `.hearing` and `.speaking`.
    let amplitude: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hudOffscreen) private var offscreen

    /// When the field last came up out of `dormant`. Nil while it is down.
    @State private var awokeAt: Date?
    /// When it started going away. Nil while it is up.
    @State private var closingAt: Date?
    /// How far through its two pulses `attention` and `failed` are.
    @State private var pulses = 0

    /// How long the arrival takes, and so how long going away takes, since
    /// the one is the other played backwards. 0.70 is the longer of the two
    /// ramps the shader runs off `act`: the depth reaches rest at 0.45 and
    /// the stretch settles at 0.70.
    static let closeDuration: Double = PresenceFieldRenderer.arrival

    var body: some View {
        Group {
            if offscreen {
                // `ImageRenderer` cannot draw an `NSViewRepresentable`: it has
                // no window to sample and comes out as a red prohibition
                // symbol, which would make every snapshot of the overlay
                // unreviewable. Same trade `VisualEffect` makes, for the same
                // reason. Nothing stands in, because the field is transparent
                // across everything a snapshot is checked for.
                Color.clear
            } else {
                // A close still has to play out even though `dormant` itself is
                // a still frame. Pausing the instant the state flips freezes
                // the band half gone and leaves that on the screen for good.
                PresenceFieldSurface(
                    frame: frame,
                    paused: (!frame.style.animating || reduceMotion) && closingAt == nil)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onAppear { sync(to: presence) }
        .onChange(of: presence) { _, next in sync(to: next) }
        .accessibilityHidden(true)
    }

    private var frame: PresenceFrame {
        let style = presence.field
        // The pulse rides on alpha rather than on thickness. A band that
        // changes thickness is a shape change and this has to stay readable as
        // the same shape between the two beats.
        let pulsing = presence == .attention || presence == .failed
        return PresenceFrame(
            style: style,
            awokeAt: awokeAt,
            closingAt: closingAt,
            heard: presence.voiced ? min(max(amplitude, 0), 1) : 0,
            alpha: pulsing && pulses < 2 ? 0.55 : 1.0)
    }

    /// Arrival and departure, the only two transitions this layer treats as
    /// events rather than as parameter changes.
    ///
    /// Everything between the six live states is a continuous move: the numbers
    /// change and the liquid carries on. Going to and from `dormant` is not,
    /// because that is the assistant arriving and leaving, and those should
    /// read as something happening rather than as a dissolve.
    private func sync(to next: Presence) {
        pulses = 0
        if next == .attention || next == .failed {
            Task { @MainActor in
                for _ in 0..<2 {
                    try? await Task.sleep(for: .milliseconds(450))
                    pulses += 1
                }
            }
        }

        guard next == .dormant else {
            closingAt = nil
            if awokeAt == nil { awokeAt = Date() }
            return
        }

        guard awokeAt != nil, closingAt == nil else { return }
        closingAt = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.closeDuration))
            // Only if nothing woke it back up meanwhile. A cleanup that runs
            // unconditionally after a sleep clobbers whatever arrived while it
            // was sleeping.
            guard presence == .dormant else { return }
            awokeAt = nil
            closingAt = nil
        }
    }
}

/// The Metal view, and the reason this is not a SwiftUI `colorEffect`.
///
/// `colorEffect` wants a compiled `.metallib`, which means a `.metal` file in
/// the target, which means `xcrun metal`, which ships with Xcode and not with
/// the Command Line Tools. That would make a full Xcode install a build
/// requirement for the whole package. Compiling the same source at runtime
/// costs one call at launch and keeps the package building on any Mac.
///
/// It also buys the thing that matters most here: `isPaused` and
/// `preferredFramesPerSecond` are first class on `MTKView`, and pacing a
/// full-screen shader by state is the entire answer to the battery question
/// `PresenceRing` raises about animating forever.
/// An `MTKView` that draws at `PresenceFieldRenderer.renderScale` pixels per
/// point rather than at the display's own density.
private final class PresenceFieldView: MTKView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let scale = PresenceFieldRenderer.renderScale
        let size = CGSize(width: newSize.width * scale, height: newSize.height * scale)
        if drawableSize != size {
            drawableSize = size
            // A parked band stretched to a new display size stays stretched
            // until something else wakes it. One frame, then it parks again.
            isPaused = false
        }
    }
}

private struct PresenceFieldSurface: NSViewRepresentable {
    let frame: PresenceFrame
    let paused: Bool

    func makeCoordinator() -> PresenceFieldRenderer { PresenceFieldRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = PresenceFieldView(frame: .zero, device: context.coordinator.device)
        // The drawable is sized by the view above, not by the display.
        view.autoResizeDrawable = false
        // The whole point of this layer: everything behind it is the person's
        // real screen, so the drawable has to carry alpha and the layer has to
        // be told not to paint the parts that are empty.
        view.layer?.isOpaque = false
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.delegate = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        // This runs on every re-render of the overlay, not only when the
        // field changed: a pill line landing, a transcript closing, a level
        // from the voice. Only a changed frame may touch the clock, because
        // the rate setter restarts it, and a restart at a still state's one
        // frame a second is a stall (see `easeInterval`). The renderer
        // decides what the change means and answers with a rate or nothing.
        guard let fps = context.coordinator.receive(frame: frame, paused: paused) else { return }
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        // Stopping is a thing the renderer does to itself once it has a
        // frame on the screen, not a thing set from here. A `draw()` called
        // on a view in the same pass that paused it asks `CAMetalLayer` for a
        // drawable it has not released yet, gets nil, and returns having drawn
        // nothing: the last lit frame stays up and `dormant` leaves a band
        // round the screen for good. Letting the clock run one more frame and
        // parking it from inside `draw` is the version that cannot miss.
        //
        // Every change starts the clock, including one into a still state:
        // `done` eases in from `acting` rather than landing, and the pointer
        // can part a parked band. The renderer parks it again from inside
        // `draw` once nothing on screen is still moving.
        view.isPaused = false
    }
}

/// Compiles the shader once, then draws one triangle per frame.
final class PresenceFieldRenderer: NSObject, MTKViewDelegate {
    /// Matches `Uniforms` in the shader source. Both sides are plain floats in
    /// declaration order with no padding needed: two `float2` first, then
    /// scalars, which keeps every member on its natural alignment.
    private struct Uniforms {
        /// First because it is the only member wider than a `SIMD2`, and both
        /// sides align a four-wide vector to sixteen bytes. Anywhere else it
        /// would sit behind padding that Swift inserts and Metal expects in a
        /// different place, and the symptom of getting that wrong is a field
        /// that renders in the wrong colour with no error anywhere.
        var tint: SIMD4<Float>
        var size: SIMD2<Float>
        var pointer: SIMD2<Float>
        var time: Float
        /// Seconds into the arrival, or, going away, seconds left of it.
        var act: Float
        var rest: Float
        /// How far the contour field has travelled, integrated from the
        /// eased drift, so a change of speed never moves the pattern.
        var travel: Float
        /// How much of the breath to take, 0 to 1.
        var pulse: Float
        /// Where in the breath, in cycles, integrated from the eased rate.
        var beat: Float
        var alpha: Float
        /// How far the band has parted round the pointer, 0 to 1.
        var part: Float
        /// The parting's clear radius and its soft edge, in screen heights.
        var partRadius: Float
        var partFeather: Float
    }

    let device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    /// Set once if the shader will not build, so a broken shader logs a line
    /// instead of a line per frame forever.
    private var broken = false
    /// Stop the clock at the end of the next frame. See `updateNSView`.
    var parkWhenDrawn = false

    /// The tint actually on screen, which chases the state's tint rather than
    /// jumping to it.
    ///
    /// A state change is instant and a colour change should not be: green
    /// arriving in one frame reads as a light being switched, and the thing
    /// this is meant to read as is a surface warming up. Eased here rather
    /// than in `PresenceFrame` because this is the only object that runs on
    /// the frame clock, and easing needs a clock.
    private var shownTint = FieldTint.steel
    private var lastDrawn: Date?
    /// Time constant of that chase. 0.30s puts it about 95% of the way there
    /// in a second, which is slow enough to see and fast enough that a task
    /// finishing in under a second still shows its colour.
    private static let tintTau = 0.30

    /// The rest of the state vector, each following its target the same way
    /// the tint does. Depth and drift take a little longer than colour so a
    /// state change reads as the liquid settling rather than switching; the
    /// two-beat alpha pulse is quick so it still reads as a beat. All
    /// guessed against the eye on 2026-09-19, never measured.
    private var rest = Chase(shown: 0, tau: 0.35)
    private var drift = Chase(shown: 0, tau: 0.50)
    private var pulseRate = Chase(shown: 0, tau: 0.40)
    private var pulseDepth = Chase(shown: 0, tau: 0.40)
    private var alpha = Chase(shown: 1, tau: 0.12)
    /// The voice. Attack is fast so a syllable lands, release slower so the
    /// band does not flicker between them.
    private var heard = Chase(shown: 0, tau: 0.04)
    private var part = Chase(shown: 0, tau: 0.18)
    /// Where the parting is drawn, following the pointer rather than sitting
    /// on it: at 20 points across, a hole that jumps between mouse events
    /// reads as flicker, and one that trails by a few frames reads as liquid.
    private var pointerX = Chase(shown: -10, tau: 0.04)
    private var pointerY = Chase(shown: -10, tau: 0.04)
    /// Integrals of the eased drift and pulse rate, in the units the shader
    /// multiplies by time. Wrapped on a long period for the same float
    /// resolution reason `time` is.
    private var travel: Double = 0
    private var beat: Double = 0

    /// The parting, in points: clear inside `partRadius` of the cursor and
    /// back to full depth `partFeather` further out. Was 0.16 of the screen
    /// height, about 157pt, and reviewed on screen on 2026-09-19 as "much
    /// smaller, should be a 20 pixel circle around the mouse", so it is 20
    /// with a soft edge. In points rather than screen heights because a
    /// cursor is the same size on every display.
    static let partRadius: Float = 20
    static let partFeather: Float = 10
    /// How much more transparent the band goes while the pointer is in it.
    /// Asked for as "10% more transparent" on 2026-09-19.
    static let partFade: Float = 0.10

    var frame = PresenceFrame(
        style: Presence.dormant.field, awokeAt: nil, closingAt: nil, heard: 0, alpha: 1)

    /// One SwiftUI update. The rate to run the clock at, or nil when nothing
    /// about the field changed and the clock is to be left exactly as it is.
    ///
    /// A new frame is by definition not settled, so it is paced as a
    /// transition: at least thirty, sixty for the exit. `draw` brings the
    /// rate down to the state's own once the ease has run.
    @MainActor
    func receive(frame next: PresenceFrame, paused: Bool) -> Int? {
        let changed = next != frame || paused != parkWhenDrawn
        frame = next
        parkWhenDrawn = paused
        guard changed else { return nil }
        return Self.rate(
            for: next.style, closing: next.closingAt != nil, settled: false, parting: false)
    }

    /// The one rule for the clock, shared by the SwiftUI update and the draw
    /// loop so the two can never disagree about it.
    ///
    /// A still state's own rate is one frame a second, and that number is
    /// never given to the view while anything is moving. Measured 2026-09-20
    /// on an `MTKView` probe: setting the rate to 1 on a running view puts
    /// its next frame exactly 1000ms out, every time, and a view unpaused at
    /// 1 draws its first frame 1.0 to 1.6s later, against 22ms for one
    /// unpaused at 60. `updateNSView` used to set the state's own rate on
    /// every entry into `done`, so every finished task froze the band mid-
    /// motion for a second, twice when the pill re-rendered during the ease,
    /// and then jumped. Reported the same day as "stops pulsating, freezes
    /// for 2 seconds, then operates the exit animation".
    ///
    /// Thirty is the slowest rate a transition reads as continuous at, and a
    /// hole following the hand wants the full sixty. Once settled, a live
    /// state runs at its own pace; a still one parks instead.
    nonisolated static func rate(
        for style: PresenceFieldStyle, closing: Bool, settled: Bool, parting: Bool
    ) -> Int {
        if closing || parting { return 60 }
        if !settled { return max(style.fps, 30) }
        return style.fps
    }

    /// How much clock one frame gets to ease across.
    ///
    /// A gap longer than a quarter of a second is a parked view waking up,
    /// or a stalled one, not a slow frame: the slowest live rate is fifty
    /// milliseconds apart. Easing across the real gap moved every chase
    /// most of the way in one frame (the old cap of half a second is 76% of
    /// a 0.35s chase), which is the pop that followed the stall above. One
    /// frame's worth, at the rate the view is running, starts the ease
    /// smoothly from wherever it was parked. Zero stays zero: the first
    /// frame ever has no clock and snaps.
    nonisolated static func easeInterval(gap: TimeInterval, rate: Int) -> TimeInterval {
        gap > 0.25 ? 1.0 / Double(max(rate, 30)) : gap
    }

    /// How long the shader's arrival ramps run, in seconds: the number the
    /// exit is played back over. Matches the 0.70 in the stretch ramp, the
    /// longer of the two in `presenceFragment`; the two have to move together.
    static let arrival: Double = 0.70

    /// Drawable pixels per point. One: the band is soft liquid with nothing
    /// in it finer than about three points. Measured 2026-09-19 on an M4
    /// Pro, GPU time per frame: at the display's density 10.8 ms before the
    /// shader's empty-pixel cull and 3.1 ms after; at this scale 2.7 ms and
    /// 0.85 ms. The first number is two thirds of a 60fps frame spent on
    /// pixels nobody could tell apart, and the band stuttered under the
    /// pointer.
    static let renderScale: CGFloat = 1

    /// Where the pointer is, in unit coordinates with a top-left origin, or
    /// nil when it is nowhere near the edge. Written by `OverlayModel.point`
    /// and read in `draw`, both on the main thread.
    ///
    /// Deliberately not part of the SwiftUI frame. When it was, every mouse
    /// event re-evaluated the overlay's whole body and ran `updateNSView`,
    /// which told the Metal view its frame rate again each time, and the
    /// parting under the cursor was reported as not smooth on 2026-09-19.
    /// The path now is one static write and one unpause.
    nonisolated(unsafe) static var pointer: CGPoint?
    /// The view on screen, so a pointer move can wake a parked field.
    nonisolated(unsafe) private static weak var live: MTKView?

    @MainActor
    static func point(at unit: CGPoint?) {
        pointer = unit
        live?.isPaused = false
    }

    override init() {
        device = MTLCreateSystemDefaultDevice()
        super.init()
    }

    @MainActor
    func attach(to view: MTKView) {
        Self.live = view
        guard let device, !broken, pipeline == nil else { return }
        do {
            let library = try device.makeLibrary(source: presenceFieldSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "presenceVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "presenceFragment")
            let format = view.colorPixelFormat
            descriptor.colorAttachments[0].pixelFormat = format
            // Premultiplied source over. The shader returns colour already
            // multiplied by its own coverage, which is what lets one pass put
            // a translucent film over the person's real screen.
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            queue = device.makeCommandQueue()
        } catch {
            // A decorative layer that will not compile is survivable. An
            // overlay that crashes on launch is not, and this one is the
            // person's only way to see anything at all.
            broken = true
            NSLog("BobHUD: presence field unavailable (\(error.localizedDescription))")
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline, let queue,
              let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let size = view.drawableSize
        // A clock that does not depend on when the view happened to appear,
        // wrapped on a long period so the float does not lose resolution in a
        // session left open for days. That is the failure mode of handing a
        // shader an epoch: by the afternoon the noise stops moving.
        let now = Date()
        let time = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 86_400)
        // The arrival clock, and going away it is the same clock run down
        // from wherever it had got to: a band that was still coming in when
        // it was told to leave turns round from there, not from full.
        var act: Double = frame.awokeAt.map { max(now.timeIntervalSince($0), 0) } ?? 0
        let closing = frame.closingAt != nil
        if let closingAt = frame.closingAt, let awokeAt = frame.awokeAt {
            let reached = min(closingAt.timeIntervalSince(awokeAt), Self.arrival)
            act = max(reached - now.timeIntervalSince(closingAt), 0)
        }
        // Exponential, off real elapsed time rather than a per-frame constant:
        // the four live rates in this file run from 20 to 60fps, and a fixed
        // step per frame would make the same transition take three times
        // longer in one state than in another.
        let dt = Self.easeInterval(
            gap: lastDrawn.map { now.timeIntervalSince($0) } ?? 0,
            rate: view.preferredFramesPerSecond)
        lastDrawn = now
        // Frozen while going away, along with `rest` below: `dormant` has no
        // depth and no colour, and easing toward it under the reversed ramp
        // would make the exit faster and greyer than the arrival it mirrors.
        let tintTarget = closing ? shownTint : frame.style.tint
        if dt <= 0 {
            shownTint = tintTarget
        } else {
            let k = Float(1 - exp(-dt / Self.tintTau))
            shownTint += (tintTarget - shownTint) * k
        }

        let style = frame.style
        let W = Float(size.width / max(size.height, 1))
        // Points to screen heights, through the backing scale, so the circle
        // is 20 points on a Retina display and on a plain one alike.
        let pixelsPerPoint = Float(size.height) / Float(max(view.bounds.height, 1))
        let radius = Self.partRadius * pixelsPerPoint / Float(max(size.height, 1))
        let feather = Self.partFeather * pixelsPerPoint / Float(max(size.height, 1))
        let pointer = Self.pointer
        let partTarget = Self.parting(
            pointer: pointer, aspect: W, rest: Float(style.rest),
            reach: radius + feather)
        if let p = pointer {
            pointerX.step(toward: Float(p.x), dt: dt)
            pointerY.step(toward: Float(p.y), dt: dt)
        }
        let heardTarget = Float(frame.heard)
        // Release slower than attack, or the band shakes between syllables.
        heard.tau = heardTarget > heard.shown ? 0.04 : 0.16

        rest.step(toward: closing ? rest.shown : Float(style.rest), dt: dt)
        drift.step(toward: Float(style.drift), dt: dt)
        pulseRate.step(toward: Float(style.pulse), dt: dt)
        pulseDepth.step(toward: style.pulse > 0 ? 1 : 0, dt: dt)
        alpha.step(toward: Float(frame.alpha), dt: dt)
        heard.step(toward: heardTarget, dt: dt)
        part.step(toward: partTarget, dt: dt)
        travel = (travel + Double(drift.shown) * dt).truncatingRemainder(dividingBy: 100_000)
        beat = (beat + Double(pulseRate.shown) * dt).truncatingRemainder(dividingBy: 100_000)

        let settled = rest.settled(at: Float(style.rest))
            && drift.settled(at: Float(style.drift))
            && pulseRate.settled(at: Float(style.pulse))
            && pulseDepth.settled(at: style.pulse > 0 ? 1 : 0)
            && alpha.settled(at: Float(frame.alpha))
            && heard.settled(at: heardTarget)
            && part.settled(at: partTarget)
            && (pointer.map {
                pointerX.settled(at: Float($0.x)) && pointerY.settled(at: Float($0.y))
            } ?? true)
            && simd_length(shownTint - tintTarget) < 0.002
            && frame.closingAt == nil
        // Written only on change: the setter restarts the clock. A view about
        // to park keeps its live rate, so the pointer or the next state can
        // wake it into a frame within thirty milliseconds rather than a
        // second; the rate of a parked view costs nothing.
        if frame.closingAt == nil && !(settled && parkWhenDrawn) {
            let fps = Self.rate(
                for: style, closing: false, settled: settled, parting: part.shown > 0.001)
            if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        }

        // The voice rides on top of the floor. 0.08 rather than the old 0.18,
        // because `rest` is now the visible depth rather than a number with
        // the screen edge buried in it, and 0.18 on top of a 0.022 floor is a
        // band that goes from a hairline to thicker than `attention` on one
        // loud syllable.
        var uniforms = Uniforms(
            tint: shownTint,
            size: SIMD2(Float(size.width), Float(size.height)),
            pointer: SIMD2(pointerX.shown, pointerY.shown),
            time: Float(time),
            act: Float(act),
            rest: rest.shown + 0.08 * heard.shown,
            travel: Float(travel),
            pulse: pulseDepth.shown,
            beat: Float(beat),
            alpha: alpha.shown * (1 - Self.partFade * part.shown),
            part: part.shown,
            partRadius: radius,
            partFeather: feather)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        // Park only once nothing is still on its way somewhere. Parking on
        // the first frame of `done` would freeze the ease from `acting` at
        // its first step, which is the jump this file was rewritten to remove.
        if parkWhenDrawn && settled { view.isPaused = true }
    }

    /// How far the band should part for a pointer at `pointer`.
    ///
    /// 1 with the pointer inside the band, falling to 0 `reach` beyond its
    /// free surface, so the liquid starts to move as the cursor approaches
    /// rather than the moment it crosses in. Distances are in screen
    /// heights, which is what the shader measures depth in.
    nonisolated static func parting(
        pointer: CGPoint?, aspect: Float, rest: Float, reach: Float
    ) -> Float {
        guard let pointer else { return 0 }
        let x = Float(pointer.x), y = Float(pointer.y)
        let near = min(x * aspect, (1 - x) * aspect, y, 1 - y)
        let inner = rest
        let outer = rest + max(reach, 0.0001)
        let t = min(max((near - inner) / (outer - inner), 0), 1)
        return 1 - t * t * (3 - 2 * t)
    }
}
