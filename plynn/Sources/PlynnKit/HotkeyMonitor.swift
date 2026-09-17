import AppKit

/// CGEventTap watcher emitting raw key events for whichever key `trigger`
/// names (default fn: flagsChanged keycode 63, .maskSecondaryFn — see
/// `HotkeyTrigger` for why that default doesn't work on every keyboard). All
/// session logic — interruption, double-tap, cancel — lives in the tested
/// `Session` state machine, not here.
public final class HotkeyMonitor {
    public var onFnDown: (() -> Void)?
    public var onFnUp: (() -> Void)?
    /// Any other keyDown (keycode passed; 53 = Escape).
    public var onKeyDown: ((Int64) -> Void)?
    /// Settable at any time — takes effect on the next event, no restart needed.
    public var trigger: HotkeyTrigger

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var watchdog: Timer?
    private var fnIsDown = false

    /// How often to confirm the tap is still listening. The app is idle
    /// between dictations, so this is cheap: one boolean read per tick.
    private let watchdogInterval: TimeInterval = 5

    public init(trigger: HotkeyTrigger = .fn) {
        self.trigger = trigger
    }

    public func start() -> Bool {
        guard install() else { return false }  // nil tap = missing Accessibility permission
        startWatchdog()
        return true
    }

    public func stop() {
        watchdog?.invalidate()
        watchdog = nil
        uninstall()
    }

    // MARK: - Tap lifecycle

    private func install() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)  // listen, never swallow (Phase 1)
        }
        guard
            let newTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: .listenOnly, eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        return true
    }

    private func uninstall() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        runLoopSource = nil
        tap = nil
    }

    // MARK: - Watchdog

    /// Poll the tap and revive it when the system has switched it off.
    ///
    /// `handle` already re-enables on `.tapDisabledByTimeout`, but that only
    /// works while the callback is still being invoked. On 2026-09-17 Plynn
    /// was found alive after two days with a tap that delivered nothing at
    /// all: no captures for fourteen hours, no disable event ever seen, mic
    /// and Accessibility grants both intact. A tap the system has torn down
    /// cannot report its own death, so the only reliable check is an outside
    /// one. Re-enabling is tried first because it is nearly free; a tap that
    /// will not come back gets rebuilt from scratch.
    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(
            timeInterval: watchdogInterval, target: WatchdogTarget(self),
            selector: #selector(WatchdogTarget.fire), userInfo: nil, repeats: true)
        // .common so the check keeps running while a menu is open or the user
        // is dragging a window, which is exactly when a long main-thread stall
        // makes the system disable the tap in the first place.
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    fileprivate func checkTap() {
        if let tap, CGEvent.tapIsEnabled(tap: tap) { return }

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) {
                NSLog("plynn: hotkey tap was disabled — re-enabled")
                resyncTriggerState()
                return
            }
        }

        uninstall()
        if install() {
            NSLog("plynn: hotkey tap was dead — rebuilt")
            resyncTriggerState()
        } else {
            // tapCreate only returns nil when Accessibility is revoked, so
            // retrying on the next tick is right: the grant can come back
            // without a relaunch.
            NSLog("plynn: hotkey tap rebuild failed — Accessibility permission?")
        }
    }

    /// The tap was deaf for a moment. If the trigger was released during that
    /// window the release is simply gone: this monitor still believes it is
    /// held, so it would emit nothing on the next press and the session would
    /// stay open forever. Resync against the live flags.
    private func resyncTriggerState() {
        if fnIsDown && !NSEvent.modifierFlags.contains(trigger.nsFlag) {
            fnIsDown = false
            onFnUp?()
        }
    }

    // MARK: - Events

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            resyncTriggerState()
            return
        }
        // The tap's run-loop source is attached to the MAIN run loop, so this
        // callback already executes on the main thread — invoke closures directly.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged && trigger.matches(keycode: keycode) {
            let down = event.flags.contains(trigger.flagMask)
            if down && !fnIsDown {
                fnIsDown = true
                onFnDown?()
            } else if !down && fnIsDown {
                fnIsDown = false
                onFnUp?()
            }
        } else if type == .keyDown {
            onKeyDown?(keycode)
        }
    }
}

/// Timer target for `HotkeyMonitor`'s watchdog.
///
/// The block form of `Timer` takes a `@Sendable` closure, and `HotkeyMonitor`
/// is a main-thread class that cannot honestly claim `Sendable`. Target/action
/// carries no such requirement, and the weak reference keeps the run loop from
/// owning the monitor.
private final class WatchdogTarget: NSObject {
    private weak var monitor: HotkeyMonitor?
    init(_ monitor: HotkeyMonitor) { self.monitor = monitor }
    @objc func fire() { monitor?.checkTap() }
}
