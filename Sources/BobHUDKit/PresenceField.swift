import MetalKit
import SwiftUI

/// What the shader is told about a state, and how often to redraw for it.
///
/// One row per named state, in `Presence.field` below. The shader has no idea
/// there are seven states: it takes three numbers and a frame rate, so adding
/// a state is a row in that table rather than a branch in Metal.
struct PresenceFieldStyle: Equatable {
    /// How thick the pool sits at rest, in units of the short screen edge.
    ///
    /// Every row was cut to 55% of its original on 2026-09-19: at the old
    /// numbers `attention` banked a third of the short edge and the field
    /// was the loudest thing on the display rather than the quietest. One
    /// factor across all seven, so the separation between states is the
    /// same and only the footprint moved.
    var rest: Double
    /// How fast the contour field travels round the edge.
    var drift: Double
    /// Mixes the palette toward the one state allowed to be red.
    var anger: Double
    /// Redraw rate while this state is up.
    var fps: Int
    /// False means one frame and then stop. A layer that redraws forever is a
    /// battery bug, which is the objection `PresenceRing` raises about itself.
    var animating: Bool
}

extension Presence {
    /// The whole mapping from named state to field.
    ///
    /// Each state has to be identifiable in peripheral vision without being
    /// looked at, so they are separated on rate first and thickness second.
    /// Reading the word takes a glance; noticing that the edge started moving
    /// does not.
    var field: PresenceFieldStyle {
        switch self {
        case .dormant:
            // Nothing. Not a thin band: the assistant is not there.
            return .init(rest: 0.058, drift: 0, anger: 0, fps: 1, animating: false)
        case .attentive:
            return .init(rest: 0.147, drift: 0.5, anger: 0, fps: 20, animating: true)
        case .hearing:
            // The one state driven from outside. `rest` here is a floor and
            // the voice adds to it, so 60fps is not decoration: it is the rate
            // the amplitude arrives at.
            return .init(rest: 0.11, drift: 0.35, anger: 0, fps: 60, animating: true)
        case .thinking:
            // Thin and fast. Work reads as travel round the edge rather than
            // as weight on it.
            return .init(rest: 0.132, drift: 3.2, anger: 0, fps: 30, animating: true)
        case .acting:
            return .init(rest: 0.157, drift: 1.1, anger: 0, fps: 30, animating: true)
        case .attention:
            // The thickest, because this is the one that has to be noticed.
            return .init(rest: 0.182, drift: 0.9, anger: 0, fps: 30, animating: true)
        case .failed:
            return .init(rest: 0.165, drift: 0.3, anger: 1, fps: 20, animating: true)
        }
    }
}

/// What the renderer is drawing this instant.
struct PresenceFrame: Equatable {
    var style: PresenceFieldStyle
    /// When it came up out of `dormant`, or nil while it is down. A date and
    /// not an elapsed time: the view redraws on its own clock and this struct
    /// only changes when the state does, so a number here would sit still for
    /// the whole 0.62s of a rupture and freeze it at its first frame.
    var awokeAt: Date?
    /// When the rupture started, or nil for "not going anywhere".
    var closingAt: Date?
    /// Where the rupture opens, in unit coordinates.
    var popAt: CGPoint
    /// Thickness on top of `style.rest`, from the voice. Only in `hearing`.
    var heard: Double
    /// Scales the whole layer's alpha, for the two states that pulse.
    var alpha: Double
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
    /// 0 to 1, only read in `.hearing`.
    let amplitude: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hudOffscreen) private var offscreen

    /// When the field last came up out of `dormant`. Nil while it is down.
    @State private var awokeAt: Date?
    /// When it started going away. Nil while it is up.
    @State private var closingAt: Date?
    /// Where the rupture opens. Picked once per closing so it is not the same
    /// spot every time, and held for all of it so the hole does not jump.
    @State private var popAt = CGPoint(x: 0.5, y: 0.5)
    /// How far through its two pulses `attention` and `failed` are.
    @State private var pulses = 0

    /// How long the rupture runs. The hole opens at a constant rate and has to
    /// clear the far corner; past this there is nothing left to draw.
    static let closeDuration: Double = 0.62

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
                // the rupture half open and leaves that on the screen for good.
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
            popAt: popAt,
            heard: presence == .hearing ? min(max(amplitude, 0), 1) : 0,
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
        popAt = CGPoint(x: .random(in: 0.18...0.82), y: .random(in: 0.18...0.82))
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
private struct PresenceFieldSurface: NSViewRepresentable {
    let frame: PresenceFrame
    let paused: Bool

    func makeCoordinator() -> PresenceFieldRenderer { PresenceFieldRenderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
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
        context.coordinator.frame = frame
        // The rupture is a fast, one-off move and it plays under `dormant`,
        // whose own rate is one frame a second. Pacing it at the destination
        // state's rate would draw it in four frames.
        view.preferredFramesPerSecond = frame.closingAt == nil ? frame.style.fps : 60
        // Stopping is a thing the renderer does to itself once it has a
        // frame on the screen, not a thing set from here. A `draw()` called
        // on a view in the same pass that paused it asks `CAMetalLayer` for a
        // drawable it has not released yet, gets nil, and returns having drawn
        // nothing: the last lit frame stays up and `dormant` leaves a band
        // round the screen for good. Letting the clock run one more frame and
        // parking it from inside `draw` is the version that cannot miss.
        context.coordinator.parkWhenDrawn = paused
        if !paused { view.isPaused = false }
    }
}

/// Compiles the shader once, then draws one triangle per frame.
final class PresenceFieldRenderer: NSObject, MTKViewDelegate {
    /// Matches `Uniforms` in the shader source. Both sides are plain floats in
    /// declaration order with no padding needed: two `float2` first, then
    /// scalars, which keeps every member on its natural alignment.
    private struct Uniforms {
        var size: SIMD2<Float>
        var popAt: SIMD2<Float>
        var time: Float
        var act: Float
        var closing: Float
        var rest: Float
        var drift: Float
        var anger: Float
        var alpha: Float
    }

    let device: MTLDevice?
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    /// Set once if the shader will not build, so a broken shader logs a line
    /// instead of a line per frame forever.
    private var broken = false
    /// Stop the clock at the end of the next frame. See `updateNSView`.
    var parkWhenDrawn = false

    var frame = PresenceFrame(
        style: Presence.dormant.field, awokeAt: nil, closingAt: nil,
        popAt: CGPoint(x: 0.5, y: 0.5), heard: 0, alpha: 1)

    override init() {
        device = MTLCreateSystemDefaultDevice()
        super.init()
    }

    @MainActor
    func attach(to view: MTKView) {
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
        let act: Double = frame.awokeAt.map { max(now.timeIntervalSince($0), 0) } ?? 0
        let closing: Double = frame.closingAt.map { now.timeIntervalSince($0) } ?? -1
        let rest: Double = frame.style.rest + 0.18 * frame.heard

        var uniforms = Uniforms(
            size: SIMD2(Float(size.width), Float(size.height)),
            popAt: SIMD2(Float(frame.popAt.x), Float(frame.popAt.y)),
            time: Float(time),
            act: Float(act),
            closing: Float(closing),
            rest: Float(rest),
            drift: Float(frame.style.drift),
            anger: Float(frame.style.anger),
            alpha: Float(frame.alpha))

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()

        if parkWhenDrawn { view.isPaused = true }
    }
}
