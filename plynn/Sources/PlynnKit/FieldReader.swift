import AppKit
import ApplicationServices

/// Reads the text of the focused UI element via Accessibility — used to see
/// what the user's correction pass did to a paste. Local-only; secure fields
/// are never read.
public enum FieldReader {
    private static let editableRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea",
    ]

    @MainActor
    static func isSecureField(_ element: AXUIElement) -> Bool {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if roleRef as? String == "AXSecureTextField" {
            return true
        }

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleRef)
        return subroleRef as? String == "AXSecureTextField"
    }

    /// Whether it is safe to synthesise Cmd-V at whatever has keyboard focus.
    ///
    /// This used to try to prove the target was editable before pasting, and it
    /// was wrong far more often than it was right. Accessibility cannot see
    /// into Chromium, Electron, or anything drawing its own text stack, so the
    /// proof failed on Slack, VS Code, Notion, every web text box and the
    /// browser in the screenshot that started this, and the dictation went to
    /// the clipboard with a "press Cmd-V" nag instead of into the field.
    ///
    /// A dictation tool that sometimes types and sometimes asks you to paste is
    /// worse than one that always types, because you cannot build a habit on
    /// it. So the only thing that blocks a paste now is a secure field, which
    /// is the one case where getting it wrong actually harms the user. If the
    /// keystroke lands somewhere that ignores it, nothing happens, which is a
    /// recoverable disappointment rather than a leaked password.
    @MainActor
    public static func focusedFieldAvailable() -> Bool {
        guard let element = focusedElement() else {
            // No focused element at all. Accessibility often cannot name the
            // target in exactly the apps that accept Cmd-V perfectly well, so
            // this is not evidence there is nowhere to type.
            return true
        }
        return !isSecureField(element)
    }

    /// Kept for callers that genuinely need to know whether the value can be
    /// written through Accessibility, as opposed to whether a paste is safe.
    @MainActor
    static func focusedValueIsSettable() -> Bool {
        guard let element = focusedElement() else { return false }
        guard !isSecureField(element) else { return false }
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        // A settable AXValue is proof the target takes text. It is not the only
        // proof, and treating it as the only proof is what made dictation land
        // on the clipboard instead of in the field.
        //
        // Chromium, Electron and anything else drawing its own text stack
        // answers this call with .success and settable = false on a text area
        // that accepts Cmd-V perfectly well: the value is not writable through
        // Accessibility even though the field is editable. Returning early on
        // that answer threw away the role, so Slack, VS Code, Discord, Notion
        // and every web text box fell to the clipboard fallback.
        //
        // So a known editable role is accepted as the second proof. The paste
        // stays guarded by the two checks that actually prevent damage: there
        // has to be a focused element, and it must not be a secure field.
        var settable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &settable) == .success,
            settable.boolValue {
            return true
        }
        return editableRoles.contains(role ?? "")
    }

    @MainActor
    public static func focusedFieldValue() -> String? {
        guard let element = focusedElement() else { return nil }
        guard !isSecureField(element) else { return nil }

        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success
        else { return nil }
        return valueRef as? String
    }

    @MainActor
    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        return focusedRef as! AXUIElement
    }
}
