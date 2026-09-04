import AppKit
import SwiftUI

/// Everything drawn on the glass.
///
/// Surfaces are laid out by region rather than by coordinate, because an agent
/// asking for "the calendar top left" does not know the size of the display and
/// should not have to. Several in the same region stack downward with an offset
/// so they read as a column rather than as one panel that failed to update.
@MainActor
public struct OverlayView: View {
    let model: OverlayModel

    public init(model: OverlayModel) { self.model = model }

    /// How much of the bottom of the display the Dock is using.
    static var bottomInset: CGFloat {
        guard let screen = OverlayWindow.active else { return 0 }
        return screen.visibleFrame.minY - screen.frame.minY
    }

    public var body: some View {
        ZStack {
            // The glass itself is deliberately nothing. Any background here,
            // even at low opacity, tints the entire display.
            Color.clear

            // Marks sit under the panels: a panel is something the person
            // asked for, a mark is something the assistant added, and when they
            // overlap the answer should not be hidden by the annotation.
            ForEach(model.markers) { marker in
                MarkerView(marker: marker, screenHeight: 0)
                    .transition(.opacity)
            }
            .zIndex(1)

            // The ring, bottom right, above everything.
            //
            // It is the one thing on the glass that is always present, so it
            // gets the corner least likely to hold work: the Dock is along the
            // bottom on most machines but the far right of it is usually empty,
            // and the eye finds a fixed point far faster than a moving one.
            PresenceRing(presence: model.presence, amplitude: model.amplitude)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                // Above the Dock, not behind it.
                //
                // The window covers the whole display including the Dock, so a
                // plain bottom-trailing alignment put the one element that is
                // always on screen in the one place it could never be seen.
                .padding(.trailing, 22)
                .padding(.bottom, Self.bottomInset + 14)
                .zIndex(9999)

            ForEach(model.surfaces) { surface in
                SurfaceCard(
                    surface: surface,
                    onDismiss: { model.close(surface.id) },
                    onDrag: { model.move(surface.id, by: $0) },
                    onGrab: { model.raise(surface.id) })
                    .frame(width: surface.width)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                                model.report(height: height, for: surface.id)
                            }
                        }
                    }
                    // `.position` and not `.position(0,0).offset(...)`.
                    //
                    // `.offset` is a visual transform: it moves what you see and
                    // leaves the hit region where the view was laid out. Every
                    // card was therefore drawn in its corner while hit-testing at
                    // the top-left of the screen, so nothing on any surface could
                    // be clicked and dragging could never start. `.position`
                    // moves the layout itself, which is what was wanted.
                    .position(model.origin(for: surface))
                    .transition(.asymmetric(
                        insertion: .modifier(
                            active: SurfaceEntrance(progress: 0, from: surface.region),
                            identity: SurfaceEntrance(progress: 1, from: surface.region)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))))
                    .zIndex(Double(surface.depth))
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: model.revision)
        .ignoresSafeArea()
    }
}

/// How a surface arrives.
///
/// It slides in from whichever edge it is anchored to, so a panel in the bottom
/// right comes up from the bottom right. Movement that agrees with position
/// reads as the thing arriving; movement that fights it reads as a glitch.
///
/// Blur on entry does most of the work: it is what makes something feel like it
/// resolved into place rather than being pasted there.
nonisolated struct SurfaceEntrance: ViewModifier, Animatable {
    var progress: Double
    let from: Region

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let travel = 26.0 * (1 - progress)
        let anchor = from.anchor
        return content
            .opacity(progress)
            .blur(radius: 9 * (1 - progress))
            .scaleEffect(0.94 + 0.06 * progress)
            .offset(
                x: travel * (anchor.x - 0.5) * 2,
                y: travel * (0.5 - anchor.y) * 2)
    }
}

/// One surface: the material, the light, the edge.
///
/// This reads as a heads-up display rather than a settings panel, and the
/// difference is almost entirely light. A HUD is dark so the content glows off
/// it, it has a bright hairline along the top where the light source would be,
/// and it sits in its own pool of shadow so it is unmistakably *above* the work
/// rather than part of it.
///
/// Everything stays under about fifteen percent opacity, because this floats
/// over somebody's real screen and a HUD that fights the work is a HUD that gets
/// turned off.
struct SurfaceCard: View {
    let surface: OverlaySurface
    let onDismiss: () -> Void
    let onDrag: (CGSize) -> Void
    let onGrab: () -> Void

    @State private var hovering = false
    @State private var lit = false
    @State private var dragging = false
    /// Where the drag stood when the current gesture began.
    @State private var base: CGSize = .zero

    var body: some View {
        // Never taller than the screen.
        //
        // A surface that overflows does not merely look wrong, it centres itself
        // off both edges and hides its own title, which is how the first
        // dashboard lost its heading and its top chart at once. `ViewThatFits`
        // takes the plain layout when it fits and swaps in a scrolling one when
        // it does not, so a short panel is still sized to its content.
        ViewThatFits(in: .vertical) {
            SurfaceView(store: surface.store)
            ScrollView(.vertical, showsIndicators: false) {
                SurfaceView(store: surface.store)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
            .frame(maxHeight: surface.maxHeight)
            // Hug the content vertically.
            //
            // The overlay proposes the whole screen to every surface, and
            // `.position` keeps proposing it, so without this a card with four
            // lines in it draws as a full-height slab with its content floating
            // in the middle. `fixedSize` tells the card to take its ideal height
            // and ignore the offer.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SurfaceChrome(chrome: surface.chrome, lit: lit))
            .overlay(alignment: .topTrailing) {
                CloseButton(action: onDismiss)
                    .padding(9)
                    .opacity(hovering ? 1 : 0)
            }
            .scaleEffect(dragging ? 1.02 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.14), value: hovering)
            .animation(.easeOut(duration: 0.12), value: dragging)
            // Drag to move. The gesture sits on the whole card and is
            // `simultaneous` so it does not swallow taps on the controls inside:
            // a HUD you can rearrange is worth much more than one you cannot,
            // and a HUD whose buttons stopped working would be worth nothing.
            .simultaneousGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            onGrab()
                        }
                        onDrag(CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height))
                    }
                    .onEnded { value in
                        dragging = false
                        base = CGSize(
                            width: base.width + value.translation.width,
                            height: base.height + value.translation.height)
                    })
            .task {
                // The hairline strikes just after the card lands, so arriving
                // reads as powering on rather than appearing.
                try? await Task.sleep(for: .milliseconds(50))
                withAnimation(.easeOut(duration: 0.28)) { lit = true }
            }
            // Force dark regardless of the system appearance: a light HUD over a
            // dark desktop is a white rectangle, and there is no version of that
            // which looks like anything but a bug.
            .environment(\.colorScheme, .dark)
    }
}

/// The three ways a surface can meet the screen.
///
/// Split out of `SurfaceCard` because it is the part that varies, and because a
/// `@ViewBuilder` switch over three chromes inside the card's own body put the
/// same exponential type-checking cost back that splitting `SurfaceView` had
/// just removed.
struct SurfaceChrome: ViewModifier {
    let chrome: Chrome
    let lit: Bool

    func body(content: Content) -> some View {
        switch chrome {
        case .card: return AnyView(card(content))
        case .bare: return AnyView(bare(content))
        case .bracket: return AnyView(bracket(content))
        }
    }

    /// Glass, a lit hairline, and its own pool of shadow.
    private func card(_ content: Content) -> some View {
        content
            // Glass is blur plus a light edge, not a dark ramp.
            //
            // The first version washed an accent gradient down from the top
            // edge and tinted the whole card, which is the look of a 2010
            // button rather than of frosted material. What actually reads as
            // glass is three things and none of them is a gradient fill: enough
            // backdrop blur to abstract what is behind, a flat wash dark enough
            // to hold white text, and a hairline along the lit edge.
            .background {
                ZStack {
                    VisualEffect(material: .hudWindow, blending: .behindWindow)
                    // Flat. Deep enough to read over a white editor, where a
                    // vibrancy material alone samples the page and goes pale.
                    Color.black.opacity(0.55)
                    // The sheen: a soft light falling across the top left.
                    //
                    // This is the piece every glassmorphism reference has and
                    // the hairline alone does not give. A pane of glass is not
                    // uniformly lit, and the gradient of the light *across* the
                    // face is what says there is a surface there at all rather
                    // than a translucent rectangle.
                    RadialGradient(
                        colors: [.white.opacity(0.16), .clear],
                        center: UnitPoint(x: 0.1, y: -0.05),
                        startRadius: 0, endRadius: 320)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                // Thickness. A second hairline just inside the bottom edge,
                // dim, as if light had travelled through the pane and come out
                // the far side. Without it a card reads as a decal.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.clear, .clear, .white.opacity(0.14)],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                    .blur(radius: 0.5)
                    .padding(1)
            }
            .overlay {
                // The inner light. One hairline inside the top edge, the way a
                // real pane catches the light above it, and a border that fades
                // as it comes down and away from that light.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.38),
                                .white.opacity(0.12),
                                .white.opacity(0.05),
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75)
            }
            .overlay(alignment: .top) {
                // The accent, kept to a short segment rather than the full
                // width, so it reads as a light source and not as a rule.
                LinearGradient(
                    colors: [.clear, HUD.accent.opacity(0.9), .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.horizontal, 28)
                    .opacity(lit ? 1 : 0)
            }
            .shadow(color: .black.opacity(0.5), radius: 30, y: 14)
    }

    /// Nothing behind it.
    ///
    /// The legibility problem a background solves has to be solved some other
    /// way, and the way is a halo: two black shadows on the content itself. A
    /// shadow follows the alpha of what it is applied to, so this darkens the
    /// screen in the shape of the glyphs and the strokes and nowhere else. A
    /// figure keeps its own outline instead of arriving inside a slab.
    private func bare(_ content: Content) -> some View {
        content
            // Five passes, tight to wide. Three was not enough over a white
            // document: the tight ones draw the outline that separates a glyph
            // from the page, and the wide ones darken enough ground around the
            // figure that it stops competing with the text underneath it.
            //
            // This is the honest limit of doing it without reading the screen.
            // A real heads-up display measures the luminance behind itself and
            // flips its ink; doing that here means capturing what is below the
            // window, which costs a screen-recording permission that a panel
            // this small has no business asking for yet.
            // Two tight passes and nothing wide.
            //
            // Five stacked shadows out to a 22-point radius did hold contrast
            // and looked like a smudge: a grey cloud around the figure, with
            // the page still readable through it. Contrast is the drawing's own
            // job now (shapes fill near-black, free text carries a plate), so
            // this only has to draw the outline that keeps a bright stroke off
            // a bright background.
            .shadow(color: .black.opacity(0.9), radius: 0.5)
            .shadow(color: .black.opacity(0.55), radius: 2.5)
    }

    /// Corner brackets, no fill.
    ///
    /// Marks a region rather than covering one, which is what the film's HUD
    /// does around anything it is paying attention to.
    private func bracket(_ content: Content) -> some View {
        content
            // A thin scrim rather than glass. Enough to hold contrast, not
            // enough to read as a window: the brackets are what marks the
            // region, and the fill only has to keep the text off the wallpaper.
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.72))
                    .padding(-8)
            }
            .overlay { Brackets(lit: lit) }
    }
}

/// Four corner marks, drawn as one shape so they animate together.
struct Brackets: View {
    let lit: Bool
    /// Nil takes the house accent, which is what a surface's chrome wants. A
    /// marker passes its own, so an outline that means "this is broken" is not
    /// drawn in the same colour as everything that means nothing in particular.
    var tint: Color?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let arm: CGFloat = 14
            Path { path in
                for corner in [
                    (CGPoint(x: 0, y: 0), CGSize(width: 1, height: 1)),
                    (CGPoint(x: size.width, y: 0), CGSize(width: -1, height: 1)),
                    (CGPoint(x: 0, y: size.height), CGSize(width: 1, height: -1)),
                    (CGPoint(x: size.width, y: size.height), CGSize(width: -1, height: -1)),
                ] {
                    let (origin, direction) = corner
                    path.move(to: CGPoint(x: origin.x + arm * direction.width, y: origin.y))
                    path.addLine(to: origin)
                    path.addLine(to: CGPoint(x: origin.x, y: origin.y + arm * direction.height))
                }
            }
            .stroke((tint ?? HUD.accent).opacity(lit ? 0.95 : 0.3), lineWidth: 1.6)
            .shadow(color: (tint ?? HUD.accent).opacity(0.65), radius: 5)
        }
        .padding(-6)
        .animation(.easeOut(duration: 0.5), value: lit)
    }
}

/// The palette, in one place so a surface and its parts cannot drift apart.
public enum HUD {
    /// Cyan rather than the system accent, which could be anything the person
    /// picked and is usually wrong against a dark translucent card.
    public static let accent = Color(red: 0.42, green: 0.83, blue: 0.96)
    public static let ink = Color.white
    public static let dim = Color.white.opacity(0.62)
    public static let faint = Color.white.opacity(0.38)

    /// Warm colours for the two states that mean something, and the house cyan
    /// for everything else.
    ///
    /// Four named tones and no free-form colour prop. A model given a hex field
    /// will use it, and a dashboard whose panels each chose their own colour is
    /// harder to read than one drawn entirely in one.
    public static let good = Color(red: 0.45, green: 0.90, blue: 0.66)
    public static let warn = Color(red: 0.99, green: 0.79, blue: 0.36)
    public static let bad = Color(red: 1.00, green: 0.45, blue: 0.42)

    public static func tone(_ name: String?) -> Color {
        switch name {
        case "good", "positive", "success": return good
        case "warn", "warning": return warn
        case "bad", "negative", "danger", "critical": return bad
        default: return accent
        }
    }
}

struct CloseButton: View {
    let action: () -> Void
    @State private var hovering = false

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.75)
        .onHover { hovering = $0 }
        .help("Dismiss")
        .accessibilityLabel("Dismiss")
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Pin the material to dark. `.environment(\.colorScheme, .dark)` governs
        // SwiftUI only; an AppKit view keeps following the system appearance and
        // turns the glass white for anyone not in dark mode.
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
