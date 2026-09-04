import AppKit

/// Which physical key activates dictation.
///
/// fn is Apple's own key — it reports a private Globe HID usage that only
/// Apple keyboards send reliably. Many third-party keyboards (NuPhy, compact
/// 65%/75% boards especially) implement their own "Fn" as a local firmware
/// layer-shift with no discrete keycode macOS ever sees, so `HotkeyMonitor`
/// hard-wired to fn's keycode never fires on them. The other cases are plain
/// modifier keys every keyboard reports the same way, as a working fallback.
public enum HotkeyTrigger: String, CaseIterable, Identifiable, Sendable {
    case fn
    /// Either Option key. This is the Chewie key: hold it and the dictation
    /// goes to the agent instead of being typed. Nobody holding a key to talk
    /// thinks about which Option they pressed.
    ///
    /// It deliberately overlaps `rightOption`, which is why that one is no
    /// longer offered as a dictation trigger. See `selectable`.
    case option
    case rightOption
    case rightCommand
    case rightControl

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fn: return "fn (Globe)"
        case .option: return "Option"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        }
    }

    /// macOS virtual keycode reported on flagsChanged for this key.
    var keycode: Int64 {
        switch self {
        case .fn: return 63
        case .option: return 58
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        }
    }

    /// The CGEventFlags bit that reflects this key's held state. Left/right
    /// share a bit — the keycode check above is what makes this side-specific.
    var flagMask: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .option: return .maskAlternate
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        }
    }

    /// Coarser NSEvent equivalent, used only for the tap-resync fallback path.
    var nsFlag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .option: return .option
        case .rightOption: return .option
        case .rightCommand: return .command
        case .rightControl: return .control
        }
    }

    func matches(keycode incoming: Int64) -> Bool {
        // Option accepts both sides; every other trigger is side-specific.
        if self == .option { return incoming == 58 || incoming == 61 }
        return incoming == keycode
    }

    /// The triggers a user may pick for DICTATION in Settings.
    ///
    /// `option` is excluded because it is the Chewie key, and `rightOption` is
    /// excluded because `option` already claims that keycode: offering it would
    /// let someone configure a dictation key that fires the agent at the same
    /// time.
    public static var selectable: [HotkeyTrigger] {
        allCases.filter { $0 != .option && $0 != .rightOption }
    }
}
