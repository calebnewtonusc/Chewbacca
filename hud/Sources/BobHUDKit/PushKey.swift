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
    /// The globe reads the flag alone, with no key code, as it always has:
    /// every flags change is forwarded and the listener treats a repeat as
    /// nothing, which is what keeps a missed event from leaving the
    /// microphone open. The others are one key code each (Apple's virtual
    /// key codes for the right-hand modifiers), because Option, Command and
    /// Control also have a left key that must not open the microphone.
    public func state(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool? {
        switch self {
        case .globe: return flags.contains(.function)
        case .rightOption: return keyCode == 61 ? flags.contains(.option) : nil
        case .rightCommand: return keyCode == 54 ? flags.contains(.command) : nil
        case .rightControl: return keyCode == 62 ? flags.contains(.control) : nil
        }
    }
}
