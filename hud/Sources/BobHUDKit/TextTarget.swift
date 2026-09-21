import AppKit
import ApplicationServices
import Foundation
import os

/// A text input somewhere on the screen, reached through the accessibility API.
///
/// This is the half of the dictation bubble that talks to other applications. A
/// bubble is dropped on a box, this works out what that box actually is, follows
/// it while its window moves, and puts the spoken words into it.
///
/// **Reading is a screen reader's job and writing is not typing.** Nothing here
/// synthesises a keystroke. `kAXSelectedText` replaces the selection, or inserts
/// at the caret when there is none, which is the same operation a paste
/// performs and is what every text field on the system already implements for
/// VoiceOver. The tier that does use the clipboard lives in the display, not
/// here, and only runs when this one says no.
///
/// **`kAXValue` is never written.** It looked like the obvious fallback and it
/// is the one that destroys work: setting the value of a field replaces its
/// whole contents, so dictating one word into a half-written message deletes the
/// message. A spike on 2026-09-21 ruled it out as a fallback for exactly that
/// reason. There is no configuration flag for it and there should not be one.
///
/// ## Threading
///
/// Every accessibility call blocks on an IPC round trip to the other
/// application, and an application that is beachballed answers when it feels
/// like it. At 10Hz on the main thread that is a stutter in a Metal view, so
/// every call in this file runs on one serial queue and the main actor only ever
/// sees the answer. `@unchecked Sendable` is the honest annotation: `AXUIElement`
/// is a CoreFoundation type that carries no conformance, and what makes this
/// safe is the queue confinement below rather than anything the compiler can
/// check.
public final class TextTarget: @unchecked Sendable {
    /// Why a bubble could not bind where it was dropped. Each case is something
    /// the person can act on, which is why they are separate: "nothing there"
    /// and "macOS has not been told to allow this" look identical on the glass
    /// and have completely different fixes.
    public enum BindFailure: Error, Sendable, Equatable {
        /// Accessibility permission has not been granted to this application.
        case notTrusted
        /// Nothing at that point, or nothing that takes text.
        case noField
        /// A password field. Refused on purpose, and refused at bind time
        /// rather than at insert time so the bubble never sits on one looking
        /// ready.
        case secure

        public var reason: String {
            switch self {
            case .notTrusted: return "accessibility not granted"
            case .noField: return "no text field there"
            case .secure: return "password field"
            }
        }
    }

    /// What the target looks like right now: where it is, and whose it is.
    public struct Look: Sendable, Equatable {
        public var frame: CGRect
        public var app: String
        public var pid: pid_t
    }

    /// The roles that take dictated text.
    ///
    /// `AXTextField` and `AXTextArea` are the two every native app uses.
    /// `AXComboBox` is the shape of a browser address bar and of Messages' own
    /// send field on some releases. `AXSearchField` is a subrole rather than a
    /// role and is reached through the subrole check below.
    private static let textRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
    ]

    /// How far up the tree to look for a text role.
    ///
    /// `AXUIElementCopyElementAtPosition` returns the deepest element under the
    /// point, and in a web view or an Electron app that is often a group or a
    /// static text inside the field rather than the field. Measured on
    /// 2026-09-21 with a probe over Messages, Terminal, Mail and Chrome: the
    /// deepest hit was the field itself in Messages and Terminal, one hop below
    /// it in Mail's compose body, and three in Chrome's omnibox. Six is that
    /// worst case doubled. Walking further starts returning the window, which
    /// accepts a value set and puts the text nowhere.
    private static let maxHops = 6

    /// How long to wait for another application to answer one call.
    ///
    /// Must stay under `Bubble.poll`, because a poll that takes longer than its
    /// own interval queues behind itself and the bubble lags the window it is
    /// following. 50ms against a 100ms poll. Measured on this machine the same
    /// day: a settled application answers a position read in under 2ms, and the
    /// only thing that ever approached the timeout was Chrome during a page
    /// load. A timeout is not an error here, it means "unchanged", so the
    /// bubble holds still for one frame instead of jumping to nowhere.
    private static let timeout: Float = 0.05

    /// The one thread allowed to touch an `AXUIElement`.
    private static let ax = DispatchQueue(label: "bob.hud.ax", qos: .userInitiated)

    private static let log = Logger(subsystem: "bob.hud", category: "bubble")

    private let element: AXUIElement
    private let pid: pid_t
    private let app: String
    public let role: String

    /// The application the field belongs to, for a label and for bringing it
    /// forward when the bubble is clicked while its window is behind.
    public var appName: String { app }
    public var appPid: pid_t { pid }

    private init(element: AXUIElement, pid: pid_t, app: String, role: String) {
        self.element = element
        self.pid = pid
        self.app = app
        self.role = role
    }

    // MARK: Permission

    /// Whether this application may read another one's windows.
    ///
    /// The display already holds Input Monitoring, because the talk key is a
    /// global flags monitor and that is the permission it needs. Accessibility
    /// is a different grant and the bubble is the first thing here to want it,
    /// so the first bubble of a fresh install can find itself refused with
    /// everything else working.
    public static var trusted: Bool { AXIsProcessTrusted() }

    /// Ask for the grant, once, with the system's own dialogue.
    ///
    /// Nothing here can grant it: the switch is in System Settings and only a
    /// person can touch it. All this does is open the dialogue that takes them
    /// there, which is better than a bubble that silently never binds.
    public static func requestTrust() {
        // The constant is an imported `var`, which Swift 6 will not let a
        // concurrent context read. Its value is stable API.
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: Binding

    /// What is under this screen point, if it takes text.
    ///
    /// The point has a top-left origin, which is what the accessibility API
    /// wants and what every screenshot and window query on the machine agrees
    /// with. AppKit's own mouse location does not, and `flipped` in the display
    /// is the one place that conversion happens.
    public static func bind(at point: CGPoint) async -> Result<TextTarget, BindFailure> {
        guard trusted else { return .failure(.notTrusted) }
        return await withCheckedContinuation { done in
            ax.async {
                done.resume(returning: bindOnQueue(at: point))
            }
        }
    }

    private static func bindOnQueue(at point: CGPoint) -> Result<TextTarget, BindFailure> {
        // Hit-test inside the owning application, not system-wide.
        //
        // The system-wide element answers with the frontmost window at that
        // point, and the bubble is drawn on a window of this application that
        // is directly over the field. Asked system-wide, every bind came back
        // with the display's own glass: the bubble bound to itself. Finding the
        // window underneath first and asking *that application* is what makes
        // the question mean "what is under the bubble" rather than "what is
        // topmost", and it needs no screen recording permission, because the
        // window list gives bounds and owner without it and only titles are
        // gated.
        guard let owner = ownerBelow(point) else { return .failure(.noField) }
        let app = AXUIElementCreateApplication(owner)
        AXUIElementSetMessagingTimeout(app, timeout)

        var hit: AXUIElement?
        let found = AXUIElementCopyElementAtPosition(
            app, Float(point.x), Float(point.y), &hit)
        guard found == .success, var element = hit else {
            // `apiDisabled` means the grant was revoked between the check above
            // and this call, which is rare and worth telling apart from an
            // empty patch of desktop.
            return .failure(found == .apiDisabled ? .notTrusted : .noField)
        }

        for hop in 0...maxHops {
            AXUIElementSetMessagingTimeout(element, timeout)
            let role = string(element, kAXRoleAttribute) ?? ""

            // Refused before the role is even considered, because a password
            // field is an `AXTextField` and would otherwise bind normally.
            if string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole {
                return .failure(.secure)
            }

            if textRoles.contains(role)
                || string(element, kAXSubroleAttribute) == kAXSearchFieldSubrole {
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                let name = NSRunningApplication(processIdentifier: pid)?
                    .localizedName ?? "that window"
                log.notice("bubble.bind role=\(role, privacy: .public) hops=\(hop) app=\(name, privacy: .public)")
                return .success(
                    TextTarget(element: element, pid: pid, app: name, role: role))
            }

            guard let parent = child(element, kAXParentAttribute) else { break }
            element = parent
        }
        return .failure(.noField)
    }

    /// The process owning the frontmost ordinary window under this point, not
    /// counting this application's own.
    ///
    /// Layer zero only. The Dock sits at 20, the menu bar higher, and this
    /// display's glass at 3, so the filter that excludes our own windows by pid
    /// also excludes every other floating panel on the machine. That is the
    /// right default: a dictation bubble belongs on a document or a message
    /// field, and a HUD from another application is not one.
    private static func ownerBelow(_ point: CGPoint) -> pid_t? {
        let mine = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }

        // The list is front to back, so the first hit is the one the person can
        // see and therefore the one they aimed at.
        for window in windows {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t, pid != mine,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"]
            else { continue }
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.05 else { continue }
            if CGRect(x: x, y: y, width: width, height: height).contains(point) {
                return pid
            }
        }
        return nil
    }

    // MARK: Following

    /// Where the target is now, or nil once it is gone.
    ///
    /// Gone covers a closed window, a quit application and a field that has
    /// been scrolled out of existence. The bubble goes orphaned rather than
    /// hunting for a replacement: a bubble that silently rebinds to whatever
    /// happens to be nearby is a bubble that puts your words in the wrong box.
    public func look() async -> Look? {
        await withCheckedContinuation { done in
            Self.ax.async { done.resume(returning: self.lookOnQueue()) }
        }
    }

    private func lookOnQueue() -> Look? {
        guard let position: CGPoint = Self.value(element, kAXPositionAttribute, .cgPoint),
              let size: CGSize = Self.value(element, kAXSizeAttribute, .cgSize)
        else { return nil }
        // A zero-sized field is a field that has been hidden rather than
        // destroyed, and following it would park the bubble in a corner.
        guard size.width > 1, size.height > 1 else { return nil }
        return Look(
            frame: CGRect(origin: position, size: size), app: app, pid: pid)
    }

    // MARK: Writing

    /// Put the caret in this field, without activating its application.
    ///
    /// The bubble takes the click itself, so the field underneath never got one
    /// and may not be focused. Setting `kAXFocused` is how a screen reader moves
    /// the caret, and it does not raise the window or steal the front app.
    public func focus() async {
        await withCheckedContinuation { done in
            Self.ax.async {
                AXUIElementSetAttributeValue(
                    self.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                done.resume()
            }
        }
    }

    /// Insert text at the caret. False means the field would not take it and
    /// the display should try the clipboard instead.
    public func insert(_ text: String) async -> Bool {
        await withCheckedContinuation { done in
            Self.ax.async { done.resume(returning: self.insertOnQueue(text)) }
        }
    }

    private func insertOnQueue(_ text: String) -> Bool {
        var settable = DarwinBoolean(false)
        let asked = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &settable)
        guard asked == .success, settable.boolValue else {
            Self.log.notice(
                "bubble.insert tier=ax refused=not_settable role=\(self.role, privacy: .public)")
            return false
        }
        let wrote = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString)
        if wrote != .success {
            Self.log.notice(
                "bubble.insert tier=ax refused=\(wrote.rawValue) role=\(self.role, privacy: .public)")
            return false
        }
        Self.log.notice("bubble.insert tier=ax chars=\(text.count)")
        return true
    }

    // MARK: Reading attributes

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success
        else { return nil }
        return raw as? String
    }

    private static func child(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success
        else { return nil }
        // A CFTypeRef holding an AXUIElement cannot be bridged with `as?`, so
        // the type is checked by its CFTypeID and then force-cast.
        guard let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// An `AXValue`-wrapped struct: a position or a size.
    private static func value<T>(
        _ element: AXUIElement, _ attribute: String, _ type: AXValueType
    ) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let wrapped = raw, CFGetTypeID(wrapped) == AXValueGetTypeID()
        else { return nil }
        let box = wrapped as! AXValue
        guard AXValueGetType(box) == type else { return nil }
        let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        guard AXValueGetValue(box, type, out) else { return nil }
        return out.pointee
    }
}
