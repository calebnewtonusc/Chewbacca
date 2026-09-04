import SwiftUI

/// Is it there, is it listening, is it working, is it stuck.
///
/// Built to the spec in `the-jarvis-problem.md` §7.1, which makes the case
/// better than this comment can: presence is a designable surface and it is
/// empty in every shipping assistant. You cannot tell whether the thing is
/// alive, so you develop the habit of assuming it is not.
///
/// The vocabulary is deliberately tiny, and the constraint that matters is that
/// each state has a **distinct motion signature identifiable in peripheral
/// vision**. Six states that all pulse are one state. Someone should know it is
/// thinking without looking directly at it.
public enum Presence: String, Sendable, CaseIterable {
    /// Running, not listening, nothing in flight. Static and nearly invisible.
    case dormant
    /// Listening for address. A slow breath.
    case attentive
    /// Hearing speech directed at it. Thickness tracks amplitude.
    case hearing
    /// A request is in flight. One arc, rotating.
    case thinking
    /// Executing something. Arc segments stepping, one per completed action.
    case acting
    /// Wants to say something, or is blocked on you. Two pulses, then hold.
    case attention
    /// An action failed in a way that may have left something in a bad state.
    /// The only state that is ever red.
    case failed

    /// Colour carries meaning here and nothing else. No branding, no theming.
    var tint: Color {
        switch self {
        case .attention: return HUD.warn
        case .failed: return HUD.bad
        default: return HUD.accent
        }
    }

    /// How long the ring may stay in this state before it is lying.
    ///
    /// An indefinite spinner is forbidden: a request that has been "thinking"
    /// for eight seconds with nothing else on screen has failed to communicate,
    /// whatever it is actually doing. Nil means the state can hold forever,
    /// which is only true of the ones that are not claiming progress.
    var patience: Duration? {
        switch self {
        case .thinking: return .seconds(8)
        case .acting: return .seconds(30)
        default: return nil
        }
    }
}

/// The ring.
///
/// Sized at 16pt, drawn with plain SwiftUI shape animations rather than a
/// per-frame timeline. That is a deliberate performance choice: this runs for
/// the entire life of the session, and a `TimelineView(.animation)` redrawing at
/// 60fps forever is a battery bug that ships to everyone. Repeating animations
/// are handed to Core Animation and cost nothing while they run.
struct PresenceRing: View {
    let presence: Presence
    /// 0 to 1, only read in `.hearing`. Input amplitude.
    let amplitude: Double

    @State private var breathing = false
    @State private var spinning = false
    @State private var pulses = 0

    private let size: CGFloat = 16

    var body: some View {
        ZStack {
            // The track. Always there, so the ring never disappears entirely:
            // dormant has to still read as *running*, or it is indistinguishable
            // from dead, which is the thing this surface exists to prevent.
            Circle()
                .stroke(presence.tint.opacity(0.22), lineWidth: 1.5)

            arc
        }
        .frame(width: size, height: size)
        .opacity(presence == .dormant ? 0.25 : 1)
        .scaleEffect(breathScale)
        .shadow(color: presence.tint.opacity(glow), radius: 6)
        .animation(.easeInOut(duration: 0.25), value: presence)
        .onAppear { restart() }
        .onChange(of: presence) { _, _ in restart() }
        .accessibilityLabel("Assistant \(presence.rawValue)")
    }

    /// The moving part, which is what actually distinguishes the states.
    @ViewBuilder
    private var arc: some View {
        switch presence {
        case .dormant, .attentive:
            EmptyView()

        case .hearing:
            // Thickness modulates with what it is hearing. Nothing rotates,
            // because rotation would read as thinking, and the difference
            // between "I am hearing you" and "I am working on it" is exactly
            // the distinction a person needs mid-sentence.
            Circle()
                .stroke(presence.tint, lineWidth: 1.5 + 2.5 * min(max(amplitude, 0), 1))
                .animation(.linear(duration: 0.06), value: amplitude)

        case .thinking:
            // One arc, eased rather than linear. A linear spinner reads as a
            // progress bar that is not progressing.
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(presence.tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    .easeInOut(duration: 1.1).repeatForever(autoreverses: false),
                    value: spinning)

        case .acting:
            // Segments, stepping. Distinct from thinking on purpose: the person
            // should be able to tell that something is being *done* to their
            // machine, not merely considered.
            Circle()
                .trim(from: 0, to: 0.62)
                .stroke(
                    presence.tint,
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .butt, dash: [2.4, 2.4]))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(
                    .linear(duration: 1.6).repeatForever(autoreverses: false),
                    value: spinning)

        case .attention, .failed:
            // Two pulses, then hold at high contrast. Never more than two: a
            // thing that pulses forever is a thing people learn to ignore, and
            // then it cannot do its job on the day it matters.
            Circle()
                .stroke(presence.tint, lineWidth: 2)
                .opacity(pulses >= 2 ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.45), value: pulses)
        }
    }

    private var breathScale: CGFloat {
        guard presence == .attentive else { return 1 }
        return breathing ? 1.08 : 0.92
    }

    private var glow: Double {
        switch presence {
        case .dormant: return 0
        case .attention, .failed: return 0.7
        default: return 0.45
        }
    }

    private func restart() {
        spinning = false
        pulses = 0
        breathing = false

        switch presence {
        case .attentive:
            // Four-second period, plus or minus eight percent. Slow enough to
            // read as breathing rather than as throbbing.
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        case .thinking, .acting:
            spinning = true
        case .attention, .failed:
            Task { @MainActor in
                for _ in 0..<2 {
                    try? await Task.sleep(for: .milliseconds(450))
                    pulses += 1
                }
            }
        default:
            break
        }
    }
}
