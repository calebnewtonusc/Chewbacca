import AppKit
import SwiftUI

/// Animation that respects the person's settings.
///
/// Every animation in this project was unconditional. Reduce Motion is a real
/// accessibility setting, set by people who get motion sick or distracted by
/// movement, and a display that floats over everything they do is the worst
/// possible place to ignore it. The diagram morph was the sharpest offender: an
/// interface that rearranges itself continuously in the corner of your eye.
///
/// Honouring it is not the same as removing the animation. What the setting
/// asks for is no *movement*, so a cross-fade is still allowed and is what a
/// morph degrades to.
public enum Motion {
    /// The standard spring, or nothing when movement is unwelcome.
    @MainActor
    public static func spring(
        _ response: Double, _ damping: Double = 0.82, reduced: Bool
    ) -> Animation? {
        reduced ? .easeOut(duration: 0.12) : .spring(response: response, dampingFraction: damping)
    }

    /// A fade, or nothing.
    @MainActor
    public static func fade(_ duration: Double, reduced: Bool) -> Animation? {
        reduced ? .easeOut(duration: min(duration, 0.1)) : .easeOut(duration: duration)
    }

    // The vocabulary. Until 2026-09-22 every call site picked its own curve:
    // nine different springs between 0.30 and 0.60 seconds and a dozen
    // eases, several of them ignoring Reduce Motion. Motion that is not
    // consistent does not read as one product, it reads as a pile of
    // components. Five named motions, and a call site picks one by what is
    // happening rather than by a number.
    //
    // Springs for anything that moves or resizes, because a spring is
    // interruptible and carries its velocity into the next target: a panel
    // re-aimed halfway there bends toward the new place instead of stopping
    // and restarting, which is most of what "fluid" means. Eases only for
    // opacity and colour, which have no momentum to keep.
    //
    // The numbers are Apple's own presets for these jobs (`.snappy` and
    // `.smooth` are 0.3 to 0.5 seconds, damping 0.85 and up, no visible
    // bounce): a utility on top of somebody's work should settle, not
    // wobble. Tuned against the eye, never measured.

    /// Something the person touched answering: a toggle, a disclosure, a
    /// button settling after a press. Fast enough to feel caused.
    @MainActor
    public static func snappy(reduced: Bool) -> Animation? {
        spring(0.28, 0.86, reduced: reduced)
    }

    /// Something arriving, leaving, growing or being re-placed: a surface,
    /// the conversation panel, a row joining a list, a thrown card landing.
    @MainActor
    public static func smooth(reduced: Bool) -> Animation? {
        spring(0.38, 0.88, reduced: reduced)
    }

    /// Data changing under the eye: a bar lengthening, a ring filling, a
    /// line redrawing. Slow enough that the change itself is seen.
    @MainActor
    public static func gentle(reduced: Bool) -> Animation? {
        spring(0.55, 0.9, reduced: reduced)
    }

    /// The pointer arriving on something. Under the 100 ms at which a
    /// response still feels like part of the action.
    @MainActor
    public static func hover(reduced: Bool) -> Animation? {
        fade(0.1, reduced: reduced)
    }

    /// A press going down. Faster than hover: the finger is already there.
    @MainActor
    public static func press(reduced: Bool) -> Animation? {
        fade(0.06, reduced: reduced)
    }

    /// The system setting, for a view with no environment to read it from.
    @MainActor
    public static var systemReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// A repeating animation is the one thing Reduce Motion should always stop:
    /// it never ends, so there is no moment at which it stops being movement.
    @MainActor
    public static func repeating(_ base: Animation, reduced: Bool) -> Animation? {
        reduced ? nil : base
    }
}

extension Optional where Wrapped == String {
    /// The string, or nothing. Reads better than a nil-coalesce inside an
    /// interpolation, where the empty case is the common one.
    var orEmpty: String { self ?? "" }
}
