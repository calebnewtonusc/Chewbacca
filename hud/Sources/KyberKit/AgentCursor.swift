import SwiftUI

/// The agent's own pointer, drawn on the glass.
///
/// The person keeps the real cursor. The agent never posts a mouse event: it
/// acts through Accessibility or the browser, neither of which needs a pointer,
/// and this is only the picture of where it is acting. Tested 2026-09-23: a
/// click posted to a background app's pid never arrived, while AXPress and a
/// set AXValue landed with the real cursor unmoved and the frontmost app
/// unchanged. So the picture is the only cursor the agent can honestly have.
///
/// It is the pill's asterisk rather than an arrow, because a second arrow on
/// the screen is a pointer the person will try to move.
public struct AgentCursor: Equatable, Sendable {
    /// The tip, in screen points with a top-left origin, like a marker.
    public var point: CGPoint
    /// Bumped on every act, so the view can pulse once per press.
    public var acts: Int

    public init(point: CGPoint, acts: Int = 0) {
        self.point = point
        self.acts = acts
    }

    /// Guessed, never measured. Long enough to cover the pause between two
    /// steps of one task, short enough that a crashed driver does not leave a
    /// pointer standing on the screen claiming to be busy.
    public static let idleLife: TimeInterval = 8
}

struct AgentCursorView: View {
    let cursor: AgentCursor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Degrees turned so far. Each press adds one arm's worth, so the mark
    /// lands looking the same as before it turned and never snaps back.
    @State private var turn: Double = 0
    @State private var pressed = false

    /// A little under the system arrow's height, about 17 points at the default
    /// cursor size. Gavin, 2026-09-23, after a 22 point version: "make it
    /// smaller, slightly smaller than a regular cursor". His own pointer stays
    /// the larger thing on the screen.
    private let size: CGFloat = 14

    /// Guessed, never measured: long enough for the green to register at a
    /// glance, short enough that three presses in a row read as three.
    private static let pressHold: Duration = .milliseconds(420)

    var body: some View {
        // The pill's own mark, so the thing in the bar and the thing doing the
        // work are recognisably one agent. White while it waits, green while it
        // presses, the same two colours the presence states already mean.
        Asterisk(arms: 6)
            .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(turn))
            .scaleEffect(pressed ? 1.25 : 1)
            .shadow(color: tint.opacity(0.6), radius: 4)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: turn)
            // Centred on the control rather than pinned by a tip: an asterisk
            // has no tip, and its middle is where it acts.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: cursor.point.x - size / 2, y: cursor.point.y - size / 2)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86),
                       value: cursor.point)
            .onChange(of: cursor.acts) {
                turn += 360 / 6
                pressed = true
                Task { @MainActor in
                    try? await Task.sleep(for: Self.pressHold)
                    pressed = false
                }
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chewbacca is working at \(Int(cursor.point.x)), \(Int(cursor.point.y))")
    }

    private var tint: Color { pressed ? Presence.acting.tint : Presence.attentive.tint }
}
