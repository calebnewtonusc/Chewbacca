import AppKit

/// The key held to talk.
///
/// The globe is the default because nothing else on the Mac claims it and
/// holding it is a gesture rather than a shortcut to remember. But a
/// keyboard that is not Apple's has no globe, and a person whose globe
/// opens the emoji picker has already given it away, so the right-hand
/// modifiers are the alternatives: each is a key nobody types with, and
/// each arrives as a flags change with its own key code, so the same
/// hold-and-release path serves all four.
public enum PushKey: String, CaseIterable, Sendable {
    case globe
    case rightOption
    case rightCommand
    case rightControl

    public static let defaultsKey = "hud.pushKey"

    /// The key chosen from the menu, or the globe.
    public static var chosen: PushKey {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(PushKey.init(rawValue:)) ?? .globe
    }

    /// In a sentence: "Hold the globe key to talk".
    public var title: String {
        switch self {
        case .globe: "the globe key"
        case .rightOption: "the right Option key"
        case .rightCommand: "the right Command key"
        case .rightControl: "the right Control key"
        }
    }

    /// On a menu.
    public var label: String {
        switch self {
        case .globe: "Globe"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        case .rightControl: "Right Control"
        }
    }

    /// This key's state after a modifier change: down, up, or nil when the
    /// change was some other key's.
    ///
    /// One key code each, Apple's virtual codes, including the globe at 63.
    /// Option, Command and Control have a left key that must not open the
    /// microphone, and the globe needs the same treatment for a different
    /// reason: `.function` rides along on events that have nothing to do with
    /// the talk key, so reading the flag alone reports a state change for
    /// somebody pressing Shift.
    ///
    /// The globe read the flag alone until 2026-09-21, defended by the fact
    /// that `beginPush` and `endPush` are idempotent, so a repeat was
    /// harmless. That held until `DoubleTap` landed on 2026-09-20 and put a
    /// *stateful* edge detector in front of them. Three hours of log then
    /// carried 200 releases against 66 presses and 18 `voice.key double`
    /// fires, each one `leave()` shutting the microphone about 100ms after it
    /// opened. Every turn ended `code=1110 partial_chars=0`, which the pill
    /// words as "Did not catch that", so the person was told they had
    /// mumbled at a microphone that had been torn down.
    ///
    /// The missed-release protection the old reading bought lives in
    /// `heldByFlags` now, where it can only close a turn.
    public func state(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool? {
        switch self {
        case .globe: return keyCode == 63 ? flags.contains(.function) : nil
        case .rightOption: return keyCode == 61 ? flags.contains(.option) : nil
        case .rightCommand: return keyCode == 54 ? flags.contains(.command) : nil
        case .rightControl: return keyCode == 62 ? flags.contains(.control) : nil
        }
    }

    /// Whether the flags alone still say this key is held.
    ///
    /// Only ever asked when `state` returned nil, and only ever used to close
    /// a turn whose release never arrived. It must not open one and must not
    /// reach the double-tap detector: a gesture is made of this key's own
    /// edges, and everything else is at most evidence that the key is no
    /// longer down.
    public func heldByFlags(_ flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .globe: return flags.contains(.function)
        case .rightOption: return flags.contains(.option)
        case .rightCommand: return flags.contains(.command)
        case .rightControl: return flags.contains(.control)
        }
    }
}
