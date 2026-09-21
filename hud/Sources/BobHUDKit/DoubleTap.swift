import AppKit
import Foundation

/// Two presses of one key in quick succession, told apart from a hold.
///
/// The globe key is held to talk. Pressed twice quickly instead, it is the
/// way out: the panel closes, the microphone shuts, a run in flight stops
/// and the glass clears. Asked for on 2026-09-20: "have double clicking the
/// world icon to activate the feature be a quick way to exit it out". One
/// gesture in and the same gesture out, so there is nothing else to learn.
public struct DoubleTap: Sendable {
    /// How closely the second press has to follow the first, measured from
    /// the first press going down rather than coming up. A hold to talk
    /// lasts longer than this on its own, so a hold followed by a press can
    /// never read as a double.
    public let interval: TimeInterval
    private var lastDown: Date?
    private var held = false

    /// The system's double-click interval by default, half a second unless
    /// the person changed it in the Mouse settings, so it feels like every
    /// other double-click on the machine.
    public init(interval: TimeInterval = NSEvent.doubleClickInterval) {
        self.interval = interval
    }

    /// The key went down. True when this press is the second of a pair, in
    /// which case the pair is spent: a third press starts over. A down with
    /// no release since the last one is another modifier changing under the
    /// held key, not a press, and counts for nothing.
    public mutating func press(at now: Date = Date()) -> Bool {
        guard !held else { return false }
        held = true
        if let last = lastDown, now >= last, now.timeIntervalSince(last) < interval {
            lastDown = nil
            return true
        }
        lastDown = now
        return false
    }

    /// The key came up.
    public mutating func release() {
        held = false
    }
}
