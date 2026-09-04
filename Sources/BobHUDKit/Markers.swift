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
        ZStack(alignment: .topLeading) {
            Brackets(lit: arrived, tint: tint)
                .frame(width: marker.rect.width, height: marker.rect.height)

            if !marker.label.isEmpty {
                Text(marker.label)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(HUD.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 0.8)
                    }
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    // Above the region, not inside it. A label inside covers the
                    // thing the mark exists to point at.
                    .offset(y: -22)
                    .fixedSize()
            }
        }
        .position(
            x: marker.rect.midX,
            y: marker.rect.midY)
        .opacity(arrived ? 1 : 0)
        .scaleEffect(arrived ? 1 : 1.06)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: arrived)
        .task {
            arrived = true
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
