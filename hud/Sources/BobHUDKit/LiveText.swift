import AppKit
import CoreGraphics

/// Dictated text that appears in the field while the person is still talking.
///
/// The recogniser revises its partials several times a second, and mostly it
/// revises the newest word or two: "send me the deck" is "send me the deck"
/// then "send me the deck for" then "send me the deck for Northwind". Typing every
/// revision straight into a field means deleting and retyping the tail on
/// every one, which reads as the text shivering. So a word is typed only once
/// it has survived one revision unchanged, and never while it is the newest
/// word. That is the LocalAgreement rule streaming Whisper systems use, with
/// the recogniser's own revisions as the chunks.
public enum LiveText {
    public static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The words `previous` and `current` agree on from the start, never
    /// including `current`'s newest word.
    public static func stablePrefix(previous: [String], current: [String]) -> [String] {
        let limit = min(previous.count, current.count - 1)
        var n = 0
        while n < limit, previous[n] == current[n] { n += 1 }
        return Array(current[..<n])
    }

    /// How to turn what is in the field into `target`: delete this many
    /// characters from the end, then type this.
    public static func edit(from typed: String, to target: String) -> (delete: Int, insert: String) {
        let old = Array(typed)
        let new = Array(target)
        var shared = 0
        while shared < old.count, shared < new.count, old[shared] == new[shared] { shared += 1 }
        return (old.count - shared, String(new[shared...]))
    }
}

/// Types into one application with synthesised key events, and remembers
/// exactly what it typed so it can take it back.
///
/// Key events rather than the clipboard, because this runs dozens of times a
/// sentence and a clipboard that changes under the person that often is a
/// clipboard they cannot use. Addressed to the pid, because an event posted to
/// the HID tap goes to whichever window holds the keyboard, and on 2026-09-22
/// that was the HUD's own glass: `front=true glass_key=true` and nothing typed.
///
/// It only ever deletes characters it typed itself. `typed` is the whole of
/// its knowledge of the field, and a correction that would reach past it is
/// not attempted.
@MainActor
public final class KeystrokeTyper {
    public let pid: pid_t
    public private(set) var typed = ""

    public init(pid: pid_t) { self.pid = pid }

    /// Make the typed text read `target`.
    public func show(_ target: String) {
        let edit = LiveText.edit(from: typed, to: target)
        for _ in 0..<edit.delete { key(51) }  // kVK_Delete
        for character in edit.insert { type(character) }
        typed = target
    }

    /// One character per event. Several fit in one, and Chrome and Electron
    /// read only the first of them.
    private func type(_ character: Character) {
        let units = Array(String(character).utf16)
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            else { continue }
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            post(event)
        }
    }

    private func key(_ code: CGKeyCode) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            else { continue }
            post(event)
        }
    }

    /// No modifiers, ever. The person is holding Control and the dictation
    /// key while the words go in, and an event that inherited Control would
    /// type a Control-letter into Terminal, which is a command.
    private func post(_ event: CGEvent) {
        event.flags = []
        event.postToPid(pid)
    }
}
