import SwiftUI

/// The object the pill and every card are made of: a slab of glass with a
/// thickness, lit from one side, standing off the screen.
///
/// The ask on 2026-09-22 was "more 3d and translucent". A flat tint with a
/// gradient border reads as a decal however clear it is, and macOS 15 has no
/// lens to borrow, so the depth is drawn. Five things make it, each one a cue
/// the eye already uses on real glass:
///
/// - a bevel: the inner edge lit where the light enters and shadowed where
///   the slab turns away, which is what says it has a thickness at all;
/// - a gloss band across the upper half, the reflection of a light above;
/// - a specular point that follows the pointer, so the object answers the
///   hand before it is clicked;
/// - a caustic, the presence colour pooling along the bottom edge the way
///   light gathers where a lens is thickest;
/// - two shadows, a tight contact one and a wide ambient one, because a single
///   soft shadow reads as a glow and not as height.
///
/// - dispersion: a faint blue and red split along the edge, the way glass
///   separates white light;
/// - the content floating a point above it, with its own small shadow, so the
///   glass reads as a layer behind the words.
///
/// The light in it follows the assistant (`hudEnergy`), and the thickness
/// follows urgency (`Urgency.thickness`): the glass says how awake and how
/// loud before a word on it is read.
///
/// Under the pointer the glass leans toward it, the words shift a pixel or
/// two against the lean, and the specular point follows. All of it is a
/// function of where the pointer is and nothing else: hold still and nothing
/// moves. The words themselves are never rotated; see `body`.
struct GlassSlab<Base: View>: ViewModifier {
    let shape: RoundedRectangle
    /// The colour of the caustic. The pill passes the presence tint, so the
    /// glass carries the state the ring is in.
    var glow: Color = HUD.accent
    /// Scales the rim. The pill is clear and needs all of it; a frosted card
    /// already has an edge from its own wash and takes about three quarters.
    var rim: Double = 1
    /// How thick the slab is, 0.6 to 1.4. Scales the bevel and the height
    /// it floats at, so an ambient card is a thin sheet and a critical one
    /// a block. One number rather than four so the cues cannot disagree.
    var thickness: Double = 1
    /// The clear variant of Liquid Glass where the OS has it.
    var clear = false
    /// How far the glass leans toward the pointer, in degrees at the edge.
    /// The pill is small enough to take more than a card, which at 400
    /// points wide swings its far edge visibly at the same angle.
    var tilt: Double = 3
    /// How far the content shifts against the lean, in points at the edge.
    /// Snapped to whole pixels, so at 2x the steps are half a point.
    var lift: CGFloat = 1.5
    @ViewBuilder let base: () -> Base

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How awake the assistant is, 0 to 1: the light in the glass follows
    /// it. See `HUDEnergyKey`.
    @Environment(\.hudEnergy) private var energy
    @Environment(\.displayScale) private var displayScale
    @State private var size: CGSize = .zero
    /// Where the pointer is over the slab, 0 to 1 each way. Nil when it is not.
    @State private var pointer: UnitPoint?

    /// Where the light sits when nobody is pointing: above and to the left,
    /// the direction every shadow on macOS already agrees on.
    private static var restingLight: UnitPoint { UnitPoint(x: 0.22, y: -0.15) }

    func body(content: Content) -> some View {
        let light = reduceMotion ? Self.restingLight : (pointer ?? Self.restingLight)
        return content
            // The content floats: its own small shadow on the glass.
            .shadow(color: .black.opacity(0.28 * thickness), radius: 1.2, y: 1.2 * thickness)
            // Clipped flat, so a fill inside it (the pill's progress) keeps
            // the glass's outline.
            .clipShape(shape)
            // The parallax, in whole device pixels. A shift of a fraction
            // of a pixel makes the renderer resample every glyph, and on
            // 2026-09-22 that turned every panel soft under the pointer.
            .offset(shift)
            // Only the glass tilts; the words never do. A 3D rotation
            // resamples whatever it is applied to, and text resampled is
            // text blurred, so the rotation stays on a layer with none.
            .background { slab(light: light) }
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, new in size = new }
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let at):
                    guard size.width > 0, size.height > 0 else { return }
                    pointer = UnitPoint(x: at.x / size.width, y: at.y / size.height)
                case .ended:
                    pointer = nil
                }
            }
            .animation(Motion.spring(0.35, 0.75, reduced: reduceMotion), value: pointer)
    }

    /// The glass on its own: body, light, edge and shadows, tilted.
    private func slab(light: UnitPoint) -> some View {
        ZStack {
            base()
            // The light in the glass powers with the assistant: dim while
            // it sleeps, full while it works. The base never changes, so
            // legibility does not either.
            Group {
                gloss
                // The specular point. 0.26 at the centre, gone by a third
                // of the width: guessed against the eye on 2026-09-22,
                // never measured.
                EllipticalGradient(
                    colors: [.white.opacity(0.26), .white.opacity(0.06), .clear],
                    center: light, startRadiusFraction: 0, endRadiusFraction: 0.55)
                // The caustic along the bottom edge. 0.20, guessed.
                EllipticalGradient(
                    colors: [glow.opacity(0.20), .clear],
                    center: .bottom, startRadiusFraction: 0, endRadiusFraction: 0.7)
            }
            .opacity(energy)
        }
        .animation(Motion.fade(0.25, reduced: reduceMotion), value: pointer == nil)
        .animation(Motion.fade(0.6, reduced: reduceMotion), value: energy)
        .clipShape(shape)
        .modifier(LiquidGlass(shape: shape, clear: clear))
        .overlay { edge.allowsHitTesting(false) }
        // Contact, then ambient. The tight one is what puts it on a
        // surface; the wide one is how far above it floats.
        .shadow(color: .black.opacity(0.32), radius: 1.5, y: 1)
        .shadow(color: .black.opacity(0.30), radius: 22 * thickness, y: 12 * thickness)
        .rotation3DEffect(.degrees(lean.x), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
        .rotation3DEffect(.degrees(lean.y), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    }

    /// Degrees about x and y. The side under the pointer dips, the way a
    /// pane pressed at that spot would.
    private var lean: (x: Double, y: Double) {
        guard let pointer, !reduceMotion else { return (0, 0) }
        return ((pointer.y - 0.5) * tilt * 2, (pointer.x - 0.5) * tilt * 2)
    }

    /// The content's shift against the lean, snapped to the pixel grid.
    private var shift: CGSize {
        guard let pointer, !reduceMotion else { return .zero }
        let snap = { (value: CGFloat) in (value * displayScale).rounded() / displayScale }
        return CGSize(
            width: snap((0.5 - pointer.x) * 2 * lift),
            height: snap((0.5 - pointer.y) * 2 * lift))
    }

    /// The reflection of a light above: a band across the upper half, inset
    /// from the edge so the bevel shows around it. Capped at 44 points so a
    /// tall card gets a lit bezel rather than a white slab over its content.
    private var gloss: some View {
        GeometryReader { proxy in
            let height = min(proxy.size.height * 0.48, 44)
            RoundedRectangle(cornerRadius: max(shape.cornerSize.width - 2, 0), style: .continuous)
                .fill(LinearGradient(
                    // To nothing, not to 0.02: any floor leaves a hard
                    // lower edge that reads as a title bar on a card.
                    colors: [.white.opacity(0.15), .white.opacity(0)],
                    startPoint: .top, endPoint: .bottom))
                .frame(height: height)
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
    }

    /// The bevel, the rim and a dark hairline outside it.
    private var edge: some View {
        ZStack {
            // The lit inner edge: a blurred stroke pushed down and right,
            // so only its top and left survive the mask.
            shape.stroke(.white.opacity(0.5), lineWidth: 2 * thickness)
                .blur(radius: 1.2 * thickness)
                .offset(x: 0.8 * thickness, y: 1.2 * thickness)
                .mask(shape)
            // The underside: the same trick pushed up, so the bottom edge
            // darkens where the slab turns away from the light.
            shape.stroke(.black.opacity(0.4), lineWidth: 3 * thickness)
                .blur(radius: 2 * thickness)
                .offset(y: -1.5 * thickness)
                .mask(shape)
            // Dispersion: glass splits white light at its edge, blue one
            // way and red the other. Two faint strokes a fraction of a
            // point apart, screened so they only ever add light. 0.22 and
            // 0.6 points are guessed against the eye, never measured.
            ZStack {
                shape.stroke(Color(red: 0.35, green: 0.85, blue: 1).opacity(0.22 * energy), lineWidth: 1)
                    .offset(x: -0.6, y: -0.4)
                shape.stroke(Color(red: 1, green: 0.35, blue: 0.75).opacity(0.18 * energy), lineWidth: 1)
                    .offset(x: 0.6, y: 0.4)
            }
            .blendMode(.screen)
            .mask(shape.inset(by: 0.5))
            // Bright at the top, almost gone a third of the way down, and
            // back at the bottom. The return is the thickness.
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.85 * rim), location: 0),
                        .init(color: .white.opacity(0.16 * rim), location: 0.4),
                        .init(color: .white.opacity(0.42 * rim), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
            // Half a point of black just outside the rim. Over a white page
            // the rim alone vanishes; this is what keeps the outline.
            shape.inset(by: -0.5).stroke(.black.opacity(0.25), lineWidth: 0.5)
        }
    }
}

/// How awake the assistant is, as the glass sees it.
///
/// Set once at the top of each window from the presence, so every slab in it
/// dims and brightens together. 1 by default: a view drawn without a
/// presence, such as a snapshot, is drawn fully lit.
struct HUDEnergyKey: EnvironmentKey {
    static let defaultValue: Double = 1
}

extension EnvironmentValues {
    var hudEnergy: Double {
        get { self[HUDEnergyKey.self] }
        set { self[HUDEnergyKey.self] = newValue }
    }
}

extension Presence {
    /// Dormant is a third lit, so the glass is still glass while it sleeps;
    /// listening is half; anything claiming work, or a result, is full.
    /// Guessed against the eye on 2026-09-22, never measured.
    var energy: Double {
        switch self {
        case .dormant: return 0.35
        case .attentive: return 0.55
        case .done: return 0.75
        default: return 1
        }
    }
}

extension Urgency {
    /// The slab for each level. Ambient is a thin sheet that barely lifts;
    /// critical is a block standing well off the screen.
    var thickness: Double {
        switch self {
        case .ambient: return 0.6
        case .normal: return 1
        case .alert: return 1.2
        case .critical: return 1.4
        }
    }

    /// The wash behind a card at this level. Normal is the 0.34 the cards
    /// carry; ambient lets more of the screen through because it is
    /// background, and the loud ones hold more ground because they are read.
    var wash: Double {
        switch self {
        case .ambient: return 0.24
        case .normal: return 0.34
        case .alert: return 0.40
        case .critical: return 0.46
        }
    }

    /// What pools at the bottom of the glass. Only the two that mean
    /// something get a warm one.
    var glow: Color {
        switch self {
        case .alert: return HUD.warn
        case .critical: return HUD.bad
        default: return HUD.accent
        }
    }
}
