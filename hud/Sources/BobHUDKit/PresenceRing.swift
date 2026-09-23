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
    /// Saying something out loud. Thickness tracks its own voice, exactly as
    /// `hearing` tracks the person's: the same signature on both sides of the
    /// exchange, because the ask on 2026-09-19 was for the reply to "make the
    /// same talking effect" as the request. Set from outside, by the bridge,
    /// from the level of the audio it is playing.
    case speaking
    /// A request is in flight. One arc, rotating.
    case thinking
    /// Executing something. Arc segments stepping, one per completed action.
    case acting
    /// The thing it was executing finished, and nothing is in flight. Holds
    /// until the next request rather than dropping straight back to `dormant`:
    /// someone who looked away for ten seconds still gets to find out it
    /// worked, and a state that clears itself the instant it arrives is a
    /// state nobody ever sees.
    case done
    /// Wants to say something, or is blocked on you. Two pulses, then hold.
    case attention
    /// An action failed in a way that may have left something in a bad state.
    /// The only state that is ever red.
    case failed

    /// The two states a voice drives, the person's and its own. Both are set
    /// from outside at the rate the level arrives, and both draw the same way.
    var voiced: Bool { self == .hearing || self == .speaking }

    /// Colour carries meaning here and nothing else. No branding, no theming.
    var tint: Color {
        switch self {
        case .acting, .done: return HUD.good
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

/// The mark: an asterisk.
///
/// Gavin, 2026-09-23, looking at the green ring: "i hate how it looks, can you
/// make it a * symbol and just have it pulsate and change color and spin when
/// thinking." So the mark is six arms from one centre, and the states keep
/// their motion signatures on it: still when dormant or done, breathing when
/// attentive, swelling with the voice, and spinning while it works. Thinking
/// adds a pulse and a slow walk around the colour wheel, because it is the one
/// state that has to be readable from the corner of an eye.
///
/// Drawn with plain SwiftUI animations rather than a per-frame timeline. This
/// runs for the entire life of the session, and a `TimelineView(.animation)`
/// redrawing at 60fps forever is a battery bug that ships to everyone.
/// Repeating animations are handed to Core Animation and cost nothing while
/// they run.
struct PresenceRing: View {
    let presence: Presence
    /// 0 to 1, only read in `.hearing` and `.speaking`. Voice amplitude.
    let amplitude: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var spinning = false
    @State private var pulsing = false
    @State private var hueWalk = false
    @State private var pulses = 0

    private let size: CGFloat = 16

    var body: some View {
        Asterisk(arms: 6)
            .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(spinAnimation, value: spinning)
            .scaleEffect(scale)
            .hueRotation(.degrees(hueWalk ? 360 : 0))
            .animation(
                Motion.repeating(.linear(duration: 3).repeatForever(autoreverses: false),
                                 reduced: reduceMotion),
                value: hueWalk)
            .opacity(presence == .dormant ? 0.3 : 1)
            .shadow(color: tint.opacity(glow), radius: 6)
            .animation(Motion.fade(0.35, reduced: reduceMotion), value: presence)
            .animation(.linear(duration: 0.06), value: amplitude)
            .onAppear { restart() }
            .onChange(of: presence) { _, _ in restart() }
            .accessibilityLabel("Chewbacca \(presence.rawValue)")
    }

    private var tint: Color { presence.tint }

    private var voice: Double { presence.voiced ? min(max(amplitude, 0), 1) : 0 }

    private var lineWidth: CGFloat {
        switch presence {
        case .attention, .failed: return 2.4
        default: return 2.0 + 1.2 * voice
        }
    }

    private var scale: CGFloat {
        switch presence {
        case .attentive: return breathing ? 1.08 : 0.92
        case .hearing, .speaking: return 1 + 0.3 * voice
        case .thinking, .acting: return pulsing ? 1.14 : 0.86
        case .attention, .failed: return pulses % 2 == 1 ? 1.25 : 1
        default: return 1
        }
    }

    /// Thinking turns steadily; acting turns faster, so something being done
    /// to the machine reads differently from something being considered.
    private var spinAnimation: Animation? {
        let period = presence == .acting ? 1.0 : 2.4
        return Motion.repeating(.linear(duration: period).repeatForever(autoreverses: false),
                                reduced: reduceMotion)
    }

    private var glow: Double {
        switch presence {
        case .dormant: return 0
        case .attention, .failed: return 0.7
        default: return 0.45
        }
    }

    private func restart() {
        // Only stop the turn when the next state does not turn, so going from
        // thinking to acting keeps spinning instead of snapping back to zero.
        let turning = presence == .thinking || presence == .acting
        if !turning { spinning = false; pulsing = false }
        if presence != .thinking { hueWalk = false }
        pulses = 0
        breathing = false
        guard !reduceMotion else { return }

        switch presence {
        case .attentive:
            // A four-second breath: slow enough to read as breathing.
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        case .thinking, .acting:
            if !spinning { spinning = true }
            if !pulsing {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
            if presence == .thinking && !hueWalk { hueWalk = true }
        case .attention, .failed:
            // Two pulses, then hold. A thing that pulses forever is a thing
            // people learn to ignore.
            Task { @MainActor in
                for _ in 0..<4 {
                    withAnimation(.easeInOut(duration: 0.22)) { pulses += 1 }
                    try? await Task.sleep(for: .milliseconds(240))
                }
            }
        default:
            break
        }
    }
}

/// Arms from the centre to the edge, evenly spaced, the first pointing up.
struct Asterisk: Shape {
    let arms: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        // Inset by half the widest stroke so round caps are not clipped.
        let radius = min(rect.width, rect.height) / 2 - 1.6
        for arm in 0..<arms {
            let angle = Double(arm) / Double(arms) * 2 * .pi - .pi / 2
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + radius * cos(angle),
                                     y: centre.y + radius * sin(angle)))
        }
        return path
    }
}
