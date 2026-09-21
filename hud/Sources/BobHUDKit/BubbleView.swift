import SwiftUI

/// The dictation bubble, drawn.
///
/// The visual language is the presence field's, not a new one: the house cyan,
/// a rim that reads as an edge rather than a border, and a breathing ring while
/// it listens. What it deliberately does not do is run the boundary shader. That
/// shader is a full-screen Metal view sampling a distance field, and putting one
/// inside a 34 point circle costs a second render pass for an effect nobody can
/// see at that size. The ring is the same idea at the size it is drawn.
///
/// Six states and six appearances. A bubble that looked the same bound and
/// unbound is the version of this feature that loses a sentence into a window
/// that closed, so every state changes something a person can see from across
/// the desk: fill, rim, ring, or the glyph in the middle.
struct BubbleView: View {
    let bubble: Bubble
    /// True while the pointer is on it, so it says what it is before it is
    /// clicked. A 34 point circle with no label is a mystery dot.
    let hovered: Bool
    /// Drives the listening ring and the unbound nudge.
    let beat: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ring
            Circle()
                .fill(fill)
                .overlay {
                    Circle().strokeBorder(rim, lineWidth: 1.2)
                }
                .overlay { glyph }
                .frame(width: Bubble.size, height: Bubble.size)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
                .shadow(color: tint.opacity(glowing ? 0.55 : 0.2), radius: glowing ? 12 : 4)
                .scaleEffect(pulse)
        }
        .overlay(alignment: .leading) { caption }
        // The whole point of the bubble is that it is over somebody else's
        // window, so it never draws outside its own circle except for the
        // caption, which is why that is an overlay rather than an HStack: an
        // HStack would move the circle when the words got longer, and the
        // circle is pinned to the field it is bound to.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: bubble.state)
    }

    // MARK: Parts

    /// The listening ring. Only `live` and `thinking` have one: a ring is the
    /// display's word for "this is happening now" and an idle bubble is not.
    @ViewBuilder private var ring: some View {
        switch bubble.state {
        case .live:
            Circle()
                .strokeBorder(tint.opacity(0.8), lineWidth: 2)
                .frame(width: Bubble.size + 10 + breath * 8, height: Bubble.size + 10 + breath * 8)
                .opacity(0.9 - breath * 0.5)
        case .thinking:
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: Bubble.size + 10, height: Bubble.size + 10)
                .rotationEffect(.degrees(reduceMotion ? 0 : beat * 360))
        default:
            EmptyView()
        }
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(bubble.state == .live ? Color.black.opacity(0.85) : HUD.ink)
            .opacity(bubble.state == .dimmed ? 0.7 : 1)
    }

    /// The label, left of the circle, only while it matters.
    ///
    /// On hover always, and unprompted while `live` so the words being heard
    /// are visible without the pointer, which is the state where the person is
    /// not touching the trackpad at all. Left, not right, because the bubble
    /// spawns beside the pill at the bottom centre and a caption to the right
    /// would run off a field that sits near the screen edge.
    @ViewBuilder private var caption: some View {
        if hovered || bubble.state == .live || bubble.state == .orphaned {
            Text(bubble.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(bubble.state == .orphaned ? HUD.warn : HUD.dim)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 260, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(.black.opacity(0.76))
                }
                .offset(x: -(Bubble.size / 2 + 8))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: Appearance

    private var tint: Color {
        switch bubble.state {
        case .orphaned: return HUD.warn
        case .unbound: return HUD.faint
        default: return HUD.accent
        }
    }

    private var fill: AnyShapeStyle {
        switch bubble.state {
        case .live:
            // Filled, not outlined. The one state where the microphone is open
            // is the one state that must be unmistakable from a metre away.
            return AnyShapeStyle(HUD.accent)
        case .dimmed:
            return AnyShapeStyle(Color.black.opacity(0.45))
        default:
            return AnyShapeStyle(Color.black.opacity(0.72))
        }
    }

    private var rim: Color {
        switch bubble.state {
        case .live: return .white.opacity(0.9)
        case .dimmed: return tint.opacity(0.35)
        case .unbound: return tint.opacity(0.7)
        default: return tint.opacity(0.85)
        }
    }

    private var symbol: String {
        switch bubble.state {
        case .unbound: return "hand.draw"
        case .idle: return "mic"
        case .dimmed: return "mic.slash"
        case .live: return "waveform"
        case .thinking: return "text.cursor"
        case .orphaned: return "exclamationmark"
        }
    }

    private var glowing: Bool {
        bubble.state == .live || bubble.state == .thinking
    }

    /// 0 to 1 and back, for the ring's breath.
    private var breath: Double {
        reduceMotion ? 0.5 : (sin(beat * 2 * .pi) + 1) / 2
    }

    /// The unbound bubble breathes very slightly, because a new one appears
    /// beside the pill while the person is reading the pill and a completely
    /// static dot is something the eye files as part of the furniture.
    private var pulse: Double {
        guard !reduceMotion, bubble.state == .unbound else { return 1 }
        return 1 + breath * 0.06
    }
}
