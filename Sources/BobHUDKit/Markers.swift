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
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(tint.opacity(0.65), lineWidth: 0.8)
                        }
                        .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
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
            withAnimation(.easeOut(duration: 0.35)) { arrived = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
