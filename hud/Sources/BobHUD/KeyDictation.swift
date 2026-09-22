import AppKit
import BobHUDKit
import Carbon
import os

/// Hold Control, then the talk key, and talk: the words are typed wherever the
/// caret is, as they are spoken. Let go and Whisper reads the sentence again
/// and corrects it in place.
///
/// Asked for 2026-09-22 in place of dragging a bubble: "instead of a bubble, we
/// could do cntl+function and it would work as talk to text", and "it needs to
/// show up as text while i speak, not some big text dump after." The bubble
/// named a destination by hand; the caret already is one.
///
/// Nothing here goes near a model or the router. The talk key
/// without Control still asks the assistant, and the two share one microphone
/// and one recogniser, forked by where the signals go rather than by a second
/// listener.
@MainActor
final class KeyDictation {
    /// The field's application, typed into by key events.
    var typer: KeystrokeTyper?
    /// The microphone is open for this session.
    var listening = false
    /// The last partial's words, for `LiveText.stablePrefix`.
    var previous: [String] = []
    /// Bumped per session, so a Whisper answer for an earlier sentence never
    /// edits a later one.
    var turn = 0
}

extension AppDelegate {
    static let keyDictation = KeyDictation()
    static let dictationLog = Logger(subsystem: "bob.hud", category: "dictation")

    func setUpDictation() {
        // Loaded at launch rather than on the first dictation, because the
        // model takes a second or two to load and the first sentence's
        // correction would otherwise find nothing listening.
        Task { await Whisper.shared.warm() }
    }

    /// The talk key moved. True means it was a dictation press and the
    /// assistant's handling must not also run.
    func dictationKey(down: Bool) -> Bool {
        let session = Self.keyDictation
        if down {
            guard NSEvent.modifierFlags.contains(.control) else { return false }
            startKeyDictation()
            return true
        }
        guard session.listening else { return false }
        if session.previous.isEmpty {
            // Nothing heard: a press by accident. Close it without a word.
            endKeyDictation()
            voice.dropPush()
        } else {
            voice.endPush()
        }
        return true
    }

    private func startKeyDictation() {
        let session = Self.keyDictation
        guard !session.listening else { return }
        // A password field turns secure input on, and every app that has one
        // focused does. Refused before the microphone opens.
        guard !IsSecureEventInputEnabled() else {
            Self.dictationLog.notice("dictation.refused reason=secure_input")
            model.fail("Secure input is on, so not typing there", hold: 3)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        session.turn += 1
        session.typer = KeystrokeTyper(pid: app.processIdentifier)
        session.previous = []
        session.listening = true
        voice.recorder = AudioRecorder()
        Task { await Whisper.shared.warm() }
        model.setPresence(.attentive, amplitude: 0)
        Self.dictationLog.notice(
            "dictation.open app=\(app.localizedName ?? "?", privacy: .public)")
        voice.beginPush()
    }

    private func endKeyDictation() {
        let session = Self.keyDictation
        session.listening = false
        session.previous = []
        model.setPresence(.dormant, amplitude: 0)
    }

    /// A voice signal during a dictation session. True: consumed.
    func keyDictationSignal(_ signal: VoiceListener.Signal) -> Bool {
        let session = Self.keyDictation
        guard session.listening, let typer = session.typer else { return false }
        switch signal {
        case .partial(let text):
            let words = LiveText.words(Spoken.punctuate(text))
            let stable = LiveText.stablePrefix(previous: session.previous, current: words)
            session.previous = words
            let target = stable.joined(separator: " ")
            // Only forward. A revision that drops back behind what is typed is
            // usually undone by the next one, and deleting on it is the
            // shiver this exists to avoid.
            if !target.isEmpty, !typer.typed.hasPrefix(target) { typer.show(target) }

        case .heard(let text):
            let final = Spoken.punctuate(text)
            typer.show(final)
            let wav = voice.recorder?.wav16k()
            endKeyDictation()
            Self.dictationLog.notice("dictation.said chars=\(final.count)")
            if let wav { correct(typer, turn: session.turn, wav: wav) }

        case .failed(let message):
            endKeyDictation()
            if typer.typed.isEmpty { model.fail(message, hold: 3) }

        case .level(let level):
            model.setPresence(level > 0.18 ? .hearing : .attentive, amplitude: level)

        case .listening:
            break
        }
        return true
    }

    /// Whisper's pass. It replaces the recogniser's text only while nothing
    /// else can have touched the field: same app in front, no key pressed since
    /// the sentence went in, and an answer of a plausible size.
    private func correct(_ typer: KeystrokeTyper, turn: Int, wav: Data) {
        let finished = Date()
        let prompt = Vocabulary.load().prefix(60).joined(separator: ", ")
        Task { @MainActor in
            guard let heard = await Whisper.shared.transcribe(wav, prompt: prompt) else { return }
            let session = Self.keyDictation
            let sinceKey = CGEventSource.secondsSinceLastEventType(
                .combinedSessionState, eventType: .keyDown)
            let before = LiveText.words(typer.typed).count
            let after = LiveText.words(heard).count
            guard session.turn == turn, !session.listening,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == typer.pid,
                  sinceKey >= Date().timeIntervalSince(finished),
                  after > 0, after * 2 >= before, after <= before * 2 + 2
            else {
                Self.dictationLog.notice("dictation.whisper skipped")
                return
            }
            let corrected = Spoken.punctuate(heard)
            guard corrected != typer.typed else { return }
            typer.show(corrected)
            Self.dictationLog.notice("dictation.whisper corrected chars=\(corrected.count)")
        }
    }
}
