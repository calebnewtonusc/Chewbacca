import AppKit
import SwiftUI

/// A mark on the screen itself, rather than a panel beside it.
///
/// This is the annotation layer from §7.3 of the spec, and the reason it is
/// called the most JARVIS-like surface with no shipped equivalent: everything
/// else in this program draws a panel *near* your work, and a panel near your
/// work is a window with better manners. A marker is drawn **on** the thing.
/// "This function has the bug" outlines the function.
///
/// Markers decay. A panel is something you asked for and can close; a mark on
/// your screen is something the assistant put there, and if it stays after it
/// stops being true it is worse than useless, because the whole layer becomes
/// something you learn to disbelieve. So every marker carries a lifetime, the
/// default is short, and staying requires being refreshed or pinned.
public struct Marker: Identifiable, Equatable, Sendable {
    public let id: String
    /// In screen points, top-left origin, matching what an agent gets from a
    /// window query or a screenshot rather than AppKit's bottom-left.
    public var rect: CGRect
    public var label: String
    public var tone: String?
    /// When this stops being drawn. Nil means it was pinned.
    public var expires: Date?

    public init(
        id: String, rect: CGRect, label: String = "",
        tone: String? = nil, expires: Date? = nil
    ) {
        self.id = id
        self.rect = rect
        self.label = label
        self.tone = tone
        self.expires = expires
    }

    /// Twelve seconds.
    ///
    /// Long enough to look up from what you were doing and read it, short
    /// enough that a stale mark is gone before you have built any trust in it.
    public static let defaultLife: TimeInterval = 12

    /// The tone that makes a mark a guide. See `GuideView`.
    public static let guideTone = "guide"
    /// How far outside its rectangle a guide is drawn, and still counts a
    /// click, in points. The ring sits this far outside the control, so a
    /// press on the ring is a press on the thing it circles.
    public static let guideReach: CGFloat = 8

    public var isGuide: Bool { tone == Marker.guideTone }
}

/// One drawn mark: corner brackets and, if it has one, a label above it.
///
/// Brackets rather than a filled rectangle, because the point of the thing is
/// the content underneath and a fill would obscure exactly what it is pointing
/// at. Corners give the eye a region without covering a single pixel of it.
struct MarkerView: View {
    let marker: Marker
    /// The overlay's own height, for flipping to AppKit's coordinate space.
    let screenHeight: CGFloat

    @State private var arrived = false

    private var tint: Color { HUD.tone(marker.tone) }

    var body: some View {
        Group {
            if marker.isGuide {
                GuideView(marker: marker)
            } else {
                brackets
            }
        }
        // Pinned by its top-left corner, not by its centre.
        //
        // `.position` centres a view inside whatever bounds its parent hands
        // it, and those bounds are not reliably the full overlay, so a mark
        // landed tens of points from the region it was describing. A mark in
        // roughly the right place is worse than no mark: it is confidently
        // wrong, and the layer stops being believable.
        //
        // Offsetting is exact and costs nothing here, because a mark is not
        // interactive: the usual objection to `.offset`, that it moves the
        // picture and leaves the hit region behind, cannot apply to something
        // that never accepts a click.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .offset(x: marker.rect.minX, y: marker.rect.minY)
        // Visible at rest, and animated in by the transition the layer applies
        // on insertion.
        //
        // It used to start at zero opacity and become visible from inside a
        // `.task`, which meant its entire visibility depended on an async side
        // effect firing. That works until it does not, and a mark that is
        // invisible is indistinguishable from one that was never sent. A
        // snapshot render caught it immediately: nothing drew at all, because
        // nothing had run the task.
        .task {
            // The brackets still strike a moment after the mark lands, so
            // arriving reads as switching on rather than appearing. Losing this
            // costs a flourish, not the mark.
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(Motion.fade(0.35, reduced: Motion.systemReduced)) { arrived = true }
        }
        .allowsHitTesting(false)
        // Announced, not hidden.
        //
        // This was `accessibilityHidden(true)`, which made the entire
        // annotation layer invisible to anyone using a screen reader. A mark
        // exists precisely to say "look at this", so hiding it from the people
        // who most need something to say that is exactly backwards.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(
            HUD.spoken(marker.tone).map { "\($0), " } .orEmpty
                + "at \(Int(marker.rect.minX)), \(Int(marker.rect.minY))")
    }

    private var spokenLabel: String {
        if marker.isGuide { return "Press this: \(marker.label)" }
        return marker.label.isEmpty ? "Marked region" : marker.label
    }

    /// The classic mark: corner brackets and, if it has one, a caption.
    private var brackets: some View {
        // The label is an overlay, so only the brackets decide the size.
        //
        // As a sibling in the ZStack it was part of the layout, so a mark with
        // a label was a different size from the region it marked, and
        // `.position` then centred the pair rather than the brackets. The mark
        // sat below the thing it was pointing at, by half the height of its own
        // caption. An annotation layer whose marks are near the right place is
        // worse than one with no marks, because it is confidently wrong.
        Brackets(lit: arrived, tint: tint)
            .frame(width: marker.rect.width, height: marker.rect.height)
            .overlay(alignment: .topLeading) {
                if !marker.label.isEmpty {
                    Text(marker.label)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(HUD.ink)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        // Glass, not a flat gray chip: the same three-layer
                        // treatment as the pill, so every mark on the glass
                        // reads as one material. 2026-09-20 feedback: the
                        // gray pop-ups didn't match the rest of the surface.
                        .background {
                            ZStack {
                                Color.white.opacity(0.14)
                                LinearGradient(
                                    colors: [.white.opacity(0.30), .clear],
                                    startPoint: .topLeading, endPoint: .center)
                                LinearGradient(
                                    colors: [.clear, .black.opacity(0.16)],
                                    startPoint: .center, endPoint: .bottom)
                            }
                        }
                        .background(.ultraThinMaterial, in: Capsule())
                        .clipShape(Capsule())
                        .modifier(LiquidGlass(
                            shape: RoundedRectangle(cornerRadius: 24, style: .continuous),
                            tint: tint.opacity(0.28)))
                        .overlay {
                            Capsule().strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.8), location: 0),
                                        .init(color: tint.opacity(0.55), location: 0.4),
                                        .init(color: .white.opacity(0.45), location: 1),
                                    ],
                                    startPoint: .top, endPoint: .bottom),
                                lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        .fixedSize()
                        // Above the region, not inside it. A label inside covers
                        // the thing the mark exists to point at, which is the
                        // one thing it must never do.
                        //
                        // Offset rather than an alignment guide: the guide
                        // version left the caption sitting inside the top-left
                        // of the marked area, and an overlay is sized by its
                        // host, so moving a child of it costs nothing.
                        .offset(y: -26)
                }
            }
    }
}

/// A guide: the mark a person asked for when they asked where to click.
///
/// Brackets say "look at this" to somebody who already knows the screen. A
/// guide says "press this" to somebody who does not: a ring around the whole
/// control, a bubble that says what to do in words, big enough to read from
/// where they sit, and a slow pulse so the eye finds it. Asked for on
/// 2026-09-20: "a little bubble will appear exactly where she needs to click".
///
/// It is the one mark that answers a click. The display takes it down and
/// tells the bridge, which looks again and shows the next step, so following
/// along never needs a word from the person. See `OverlayModel.hit(at:)`.
struct GuideView: View {
    let marker: Marker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    /// Above the control unless the control is at the top of the screen,
    /// where above is off the glass. 72 is the bubble's height plus its
    /// gap plus the menu bar, roughly; a bubble that starts under the menu
    /// bar is still readable, one that starts above the screen is not.
    private var bubbleBelow: Bool { marker.rect.minY < 72 }

    var body: some View {
        let tint = HUD.accent
        let ring = ZStack {
            // The halo: a second ring that grows and fades, over and over.
            // The only moving part, and the part Reduce Motion removes.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(pulsing ? 0 : 0.55), lineWidth: 2)
                .scaleEffect(pulsing ? 1.22 : 1)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint, lineWidth: 2.5)
                .shadow(color: tint.opacity(0.75), radius: 8)
        }
        // Outside the control's own edge, so the ring frames the control
        // rather than sitting on its border.
        .padding(-Marker.guideReach)
        .frame(width: marker.rect.width, height: marker.rect.height)
        Group {
            if marker.label.isEmpty {
                ring
            } else {
                // The `if` stays out here. An alignment guide set on a view
                // inside a conditional inside an overlay is dropped, and the
                // bubble then centres on the control it exists to point at,
                // covering it. It had done that since the bubble shipped;
                // the snapshot test only caught it on 2026-09-20, once its
                // tolerance stopped passing on ground-text noise.
                ring.overlay(alignment: bubbleBelow ? .bottom : .top) {
                    bubble(tint: tint)
                        // Clear of the ring, whichever side it is on: the
                        // ring's reach plus a gap for the bubble's tail.
                        // Written against `height` and a constant, not
                        // against each other: `$0[.top]` inside the second
                        // guide returned the first guide's explicit value,
                        // so the bottom guide came out at the plain bottom
                        // and a bubble meant to hang below the control sat
                        // on it instead.
                        .alignmentGuide(.top) { $0.height + Marker.guideReach + 8 }
                        .alignmentGuide(.bottom) { _ in -(Marker.guideReach + 8) }
                }
            }
        }
        .onAppear {
            withAnimation(Motion.repeating(
                .easeInOut(duration: 1.6).repeatForever(autoreverses: false),
                reduced: reduceMotion)
            ) {
                pulsing = true
            }
        }
    }

    private func bubble(tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Text(marker.label)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(HUD.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            // The same glass as the pill, not a flat gray card: a white
            // tint so it reads over anything behind it, light entering
            // top left, an underside that darkens like a lens. 2026-09-20
            // feedback: the gray pop-ups and bubbles didn't match the rest
            // of the surface, which is meant to be glass throughout.
            .background {
                ZStack {
                    Color.white.opacity(0.16)
                    LinearGradient(
                        colors: [.white.opacity(0.34), .clear],
                        startPoint: .topLeading, endPoint: .center)
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.20)],
                        startPoint: .center, endPoint: .bottom)
                }
            }
            .background(.ultraThinMaterial, in: shape)
            .clipShape(shape)
            .modifier(LiquidGlass(shape: shape, tint: tint.opacity(0.3)))
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.85), location: 0),
                            .init(color: tint.opacity(0.55), location: 0.4),
                            .init(color: .white.opacity(0.5), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            }
            // The tail, aimed at the control, frosted like the body it
            // hangs off rather than a flat black wedge.
            .overlay(alignment: bubbleBelow ? .top : .bottom) {
                Tail(down: !bubbleBelow)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Tail(down: !bubbleBelow)
                            .fill(Color.white.opacity(0.12))
                    }
                    .frame(width: 16, height: 8)
                    .offset(y: bubbleBelow ? -8 : 8)
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
            // Its own width, not the control's: a bubble on a 30-point
            // button would otherwise wrap one word per line.
            .fixedSize()
    }
}

/// The bubble's tail: a small triangle pointing at the control.
struct Tail: Shape {
    let down: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if down {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}
