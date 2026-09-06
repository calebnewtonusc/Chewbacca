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
