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

    public var body: some View {
        ZStack {
            // The glass itself is deliberately nothing. Any background here,
            // even at low opacity, tints the entire display.
            Color.clear

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
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.revision)
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
            .background {
                ZStack {
                    // Dark and translucent: the wallpaper and windows underneath
                    // stay legible, and light text reads as emitted rather than
                    // printed.
                    VisualEffect(material: .hudWindow, blending: .behindWindow)
                    // Deep enough to read as a HUD over a *light* window too.
                    //
                    // At 0.36 the card was a pale grey rectangle over a white
                    // editor, because a vibrancy material samples what is behind
                    // it and there was not enough ink on top to win.
                    Color.black.opacity(0.62)

                    // A wash of the accent from the top edge, as if lit from the
                    // hairline above it.
                    LinearGradient(
                        colors: [HUD.accent.opacity(0.16), .clear],
                        startPoint: .top, endPoint: .center)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .top) {
                // The light source. One bright hairline, brightest in the middle,
                // which is what makes the whole card look lit instead of drawn.
                LinearGradient(
                    colors: [.clear, HUD.accent.opacity(0.85), .clear],
                    startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .opacity(lit ? 1 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                HUD.accent.opacity(0.34),
                                .white.opacity(0.07),
                                .clear,
                            ],
                            startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.55), radius: 26, y: 12)
            .shadow(color: HUD.accent.opacity(0.14), radius: 18)
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
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeOut(duration: 0.5)) { lit = true }
            }
            // Force dark regardless of the system appearance: a light HUD over a
            // dark desktop is a white rectangle, and there is no version of that
            // which looks like anything but a bug.
            .environment(\.colorScheme, .dark)
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
