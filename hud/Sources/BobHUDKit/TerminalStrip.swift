import SwiftUI

/// One thin line under the pill: a dot in the ring's colour for the state,
/// and what the tab is doing. Hidden when the terminal is idle. The whole
/// strip is the button; a click asks the bridge to bring the tab forward.
///
/// Sizes below are guessed, never measured, except the placement offset in
/// `OverlayView.swift`, which carries its own evidence.
struct TerminalStripView: View {
    let strip: TerminalStrip
    let onFocus: () -> Void
    @State private var hovering = false
    /// Whether this view pushed the pointing hand. The strip disappears the
    /// moment the terminal goes idle, which can happen with the pointer over
    /// it: the `false` branch of `onHover` never runs then, and the push is
    /// never popped, so the cursor stays a hand over the whole screen.
    @State private var pushedCursor = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch strip.state {
        case .running, .done: return HUD.good
        case .waiting: return HUD.warn
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(strip.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HUD.ink.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(hovering ? 0.45 : 0.22), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { onFocus() }
        .onHover { over in
            hovering = over
            if over, !pushedCursor {
                NSCursor.pointingHand.push()
                pushedCursor = true
            } else if !over, pushedCursor {
                NSCursor.pop()
                pushedCursor = false
            }
        }
        .onDisappear {
            if pushedCursor {
                NSCursor.pop()
                pushedCursor = false
            }
        }
        .animation(Motion.fade(0.14, reduced: reduceMotion), value: hovering)
        .accessibilityLabel("Terminal: \(strip.text)")
        .accessibilityAction(named: "Show the terminal") { onFocus() }
    }
}
