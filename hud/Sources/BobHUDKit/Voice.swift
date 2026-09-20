import AVFoundation
import Foundation
import os
import Speech

/// Listening.
///
/// The display could already draw anything and there was no way to ask it for
/// anything without a terminal, which makes it a rendering target rather than an
/// assistant. The spec's first property is zero invocation cost: the cost of
/// engaging should be the cost of speaking, and every click between wanting help
/// and getting it is a tax that kills the behaviour.
///
/// Recognition is pinned on-device. That is not only a privacy position, though
/// it is that: a HUD that ships audio to a server cannot be left listening in a
/// room where other people are talking, and one that cannot be left listening is
/// one you have to remember to turn on, which is the tax again.
///
/// Two modes, because they answer different objections:
///
/// - **Push to talk** needs no wake word, no continuous audio, and no trust. Hold
///   a key, speak, release.
/// - **Wake** listens continuously and acts only on an utterance containing the
///   wake word. It is what the films depict and it costs a microphone that is
///   always open, so it is opt-in and it says so in the menu.
///
/// What was heard is shown before it is acted on. Every revision the recogniser
/// makes goes out as `.partial` while the person is still talking, and the turn
/// closes as one `.heard`: on the final, or on the last partial once
/// `commitGrace` has passed since the key came up, whichever lands first. The
/// turn counter is what makes the second arrival inert.
@MainActor
public final class VoiceListener {
    public enum Mode: String, Sendable {
        case off
        case pushToTalk
        case wake
    }

    /// What the listener tells the app.
    public enum Signal: Sendable {
        /// Input level, 0 to 1, for the ring.
        case level(Double)
        /// What the recogniser thinks it has heard so far. Revised freely,
        /// several times a second, and never something to act on: draw it, do
        /// not send it. In wake mode the wake word is already stripped and
        /// nothing is shown until it has been said.
        case partial(String)
        /// A complete utterance, wake word already stripped.
        case heard(String)
        /// Recognition state changed.
        case listening(Bool)
        case failed(String)
    }

    public var onSignal: ((Signal) -> Void)?
    public private(set) var mode: Mode = .off

    /// Words that mean "I am talking to you".
    ///
    /// Matched against a lowercased transcript, so "hey chewy" and "ok chewie"
    /// both land. Deliberately forgiving: a wake word that needs to be said
    /// precisely is one people stop using.
    public var wakeWords: [String] = ["chewy", "chewie", "chewbacca", "jarvis"]

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// The last transcript acted on, so one utterance is not fired twice as the
    /// recogniser refines it.
    private var lastFired = ""
    /// When it was fired. Without this the suppression is permanent, and asking
    /// for the same thing twice in one session silently does nothing the second
    /// time, which is a thing people do constantly: "show me my week" in the
    /// morning and again after lunch is two requests, not a repeat.
    private var lastFiredAt = Date.distantPast
    private var silenceTimer: Timer?
    /// The wait after a key release before the last partial is committed. See
    /// `commitGrace`.
    private var commitTimer: Timer?
    /// Backstop for a final transcript that never arrives after a key release.
    private var finalTimeout: Timer?

    /// Bumped whenever a recognition task is torn down. Every callback and
    /// timer for a turn captures the value it started with and drops itself on
    /// a mismatch, so a final that arrives after the commit timer already sent
    /// the last partial, or after the person cancelled, cannot reach `fire`.
    /// `fire`'s repeat check only catches an identical string; a final that
    /// differed from the last partial by one word used to be a second request.
    private var turn = 0
    /// The newest partial of the open turn, so a key release can commit what
    /// was heard without waiting for a final the recogniser is slow to send.
    private var latestPartial = ""
    /// When the key came up, so the final's lag can be logged and
    /// `commitGrace` moved from a research band to a measurement.
    private var releasedAt: Date?
    /// The key is down. Read only by `beginPush`'s permission callback: on the
    /// first press of a session the two permission hops can finish after the
    /// key has already come up, and opening the microphone then leaves it open
    /// with nothing to close it, which is the one thing this mode promises
    /// never happens.
    private var pushHeld = false
    /// Both permissions landed once this session. `authorize` is two async hops
    /// through system queues before `start()` can open the microphone, and no
    /// partial can land before the microphone does. Not measured; cheap to
    /// skip.
    private var authorized = false
    /// The throwaway request that wakes the recogniser. See `warmUp`.
    private var warmTask: SFSpeechRecognitionTask?

    /// How long after the key comes up the last partial is committed as the
    /// transcript if the final has not landed. The on-device recogniser's final
    /// lags the last audio buffer, and it revises partials in that gap,
    /// capitalisation and proper nouns most of all ("text sara" becomes "text
    /// Sarah"), so waiting is what buys the corrected name. 0.4 is the middle
    /// of the 300 to 500ms band the research brief for this change gives for
    /// the wait; guessed, never measured on this machine. Every push-to-talk
    /// turn logs a `voice.turn` line with its release-to-commit lag and which
    /// side won; `log show --predicate 'subsystem == "bob.hud"'` reads them
    /// back. Measured 2026-09-19 on a MacBook Pro, macOS 15.7.3: the
    /// recogniser never sent a final at all. Every release came back as
    /// error 1101 some 20 to 40ms after the microphone closed, so the error
    /// path commits the last partial and the grace has never had to fire.
    var commitGrace: TimeInterval = 0.4

    /// The floor under a turn that produced no partial at all: nothing to
    /// commit at the grace, so wait for a final, and past this give up so the
    /// task is cleared and the next press is not silently dead. 3s: guessed,
    /// never measured.
    private static let finalFloor: TimeInterval = 3

    private static let log = Logger(subsystem: "bob.hud", category: "voice")

    public init() {}

    // MARK: Permission

    /// Ask once, and report honestly rather than failing silently.
    ///
    /// A denied microphone is the single most confusing failure this component
    /// can have, because everything else keeps working and the ring simply never
    /// moves. It has to say so.
    /// Ask for the two permissions, in order, and report whether both landed.
    ///
    /// Both closures are explicitly `@Sendable`, and that is load-bearing rather
    /// than tidiness. This class is `@MainActor`, so a closure written inside it
    /// inherits main-actor isolation; both of these APIs call back on their own
    /// background queue. The runtime checks the executor on entry, finds the
    /// wrong one, and traps: `dispatch_assert_queue_fail`, SIGTRAP, the whole
    /// app gone. It killed the display the first time anybody granted speech
    /// recognition, which is the worst possible moment for it, because the
    /// permission is recorded and the crash then looks like the grant did it.
    /// `@Sendable` opts the closures out of the inherited isolation and the
    /// `Task { @MainActor }` hops back deliberately.
    /// `done` is `@MainActor` because both call sites act on the result by
    /// touching this class, and it is always invoked from inside the hop below.
    /// Typing it that way is what lets `beginPush` call `start()` directly
    /// instead of opening a second unchecked path back onto the main actor.
    public func authorize(_ done: @escaping @MainActor @Sendable (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { @Sendable status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.onSignal?(.failed("Speech recognition not permitted"))
                    done(false)
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { @Sendable granted in
                    Task { @MainActor in
                        if !granted { self.onSignal?(.failed("Microphone not permitted")) }
                        done(granted)
                    }
                }
            }
        }
    }

    // MARK: Control

    public func setMode(_ next: Mode) {
        guard next != mode else { return }
        mode = next
        switch next {
        case .off:
            stop()
        case .wake:
            authorize { ok in if ok { self.start() } }
        case .pushToTalk:
            // Nothing opens until the key goes down. That is the point of the
            // mode: no audio is captured while you are not holding it.
            stop()
        }
    }

    /// Ask for the permissions and wake the recogniser now, at the moment the
    /// person chose the mode, rather than under their first sentence. Not
    /// called from `setMode`, which the tests drive in a process that has no
    /// usage strings and would be killed on the first permission call.
    public func prepare() {
        if authorized { warmUp(); return }
        authorize { ok in
            self.authorized = ok
            if ok { self.warmUp() }
        }
    }

    /// Start the system's local recognition service before it is needed.
    ///
    /// The service starts on the first request and loads its model then. On
    /// 2026-09-19 the first six presses after the mode was chosen found it
    /// unable to lock the model (MobileAssetError 6582) and every one came
    /// back empty with error 1101 on release; the next press, twelve minutes
    /// later, worked. One request holding a tenth of a second of silence
    /// makes that first start happen here. No audio is captured: the buffer
    /// is zeros this class makes, and the microphone stays shut.
    private func warmUp() {
        guard warmTask == nil, let recognizer, recognizer.isAvailable else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        if let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
           let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600),
           let samples = silence.floatChannelData {
            silence.frameLength = 1_600
            samples[0].update(repeating: 0, count: 1_600)
            request.append(silence)
        }
        request.endAudio()
        Self.log.notice("voice.warm on_device=\(recognizer.supportsOnDeviceRecognition)")
        warmTask = recognizer.recognitionTask(with: request) { @Sendable [weak self] _, error in
            let code = (error as NSError?)?.code ?? 0
            Task { @MainActor in
                Self.log.notice("voice.warm done code=\(code)")
                self?.warmTask = nil
            }
        }
    }

    /// Held key went down. Only meaningful in push-to-talk.
    public func beginPush() {
        guard mode == .pushToTalk else { return }
        pushHeld = true
        // Every way `start()` can decline, in one persisted line, because a
        // press that opens nothing looks the same from outside whichever it
        // was.
        Self.log.notice(
            "voice.press authorized=\(self.authorized) open=\(self.task != nil) available=\(self.recognizer?.isAvailable ?? false) on_device=\(self.recognizer?.supportsOnDeviceRecognition ?? false) engine=\(self.engine.isRunning)"
        )
        if authorized { start(); return }
        authorize { ok in
            self.authorized = ok
            if ok, self.pushHeld { self.start() }
        }
    }

    /// Held key came up. Close the microphone, then commit the turn.
    ///
    /// The two halves have to happen in that order and they are not the same
    /// event. Releasing the key ends the person's turn, so the microphone shuts
    /// immediately and the level drops: nothing is captured after the key is
    /// up, which is the promise the mode makes. But the recogniser has not
    /// produced its final transcript yet, and `stop()` cancels the task, which
    /// throws it away. Calling both here is why releasing the key used to lose
    /// the whole utterance once the silence timer stopped firing for it. So the
    /// task is left alive and two timers close the turn instead: the grace
    /// commits the last partial if the final is slow, and the floor gives up if
    /// there was nothing to commit.
    ///
    /// A release with no microphone open (the recogniser closed the turn on its
    /// own under the held key, or the permission hops have not finished) has
    /// nothing to close and arms nothing.
    public func endPush() {
        guard mode == .pushToTalk else { return }
        pushHeld = false
        guard engine.isRunning else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        closeMicrophone()
        request?.endAudio()
        releasedAt = Date()
        armCommit()
        armFinalFloor()
    }

    /// The person took the press back: Escape, or the X on the pill, while the
    /// microphone is open or the turn is still draining. `stop()` bumps `turn`,
    /// so a final that lands after this is dropped, which is what a cancel
    /// needs. In wake mode the utterance is dropped the same way but the
    /// listener reopens, because the mode was not what was cancelled.
    public func cancelPush() {
        pushHeld = false
        if mode == .wake { restartIfWaking() } else { stop() }
    }

    /// Shut the microphone without touching the recognition task.
    private func closeMicrophone() {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        onSignal?(.level(0))
    }

    // MARK: Engine

    private func start() {
        guard task == nil else { return }
        guard let recognizer, recognizer.isAvailable else {
            onSignal?(.failed("Speech recogniser unavailable"))
            return
        }
        latestPartial = ""
        releasedAt = nil

        // `nonisolated(unsafe)`: the tap below captures this and calls
        // `append` on the audio thread, and the class is not Sendable, so
        // Swift 6 flags the capture. The crossing is the one the API is built
        // for: Apple's live-audio sample appends from exactly this tap and
        // calls `endAudio` from the main thread, which is all this class does
        // with it. Narrower than the `@preconcurrency import` the compiler
        // suggests, which would also silence the result object the callback
        // below is careful not to send.
        nonisolated(unsafe) let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device or not at all. `requiresOnDeviceRecognition` is a request
        // rather than a guarantee on older hardware, so it is paired with the
        // availability check above and the mode stays opt-in.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // `@Sendable`, for the same reason as the two closures in `authorize`,
        // and it matters most here: this one runs on the realtime audio thread,
        // once per 1024-frame buffer. Inheriting this class's main-actor
        // isolation meant the runtime checked the executor on every buffer and
        // trapped on the first, roughly 23ms after the microphone opened.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) {
            @Sendable [weak self] buffer, _ in
            request.append(buffer)
            guard let level = Self.level(of: buffer) else { return }
            Task { @MainActor in self?.onSignal?(.level(level)) }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            onSignal?(.failed("Could not open the microphone"))
            return
        }
        onSignal?(.listening(true))
        Self.log.notice("voice.start on_device=\(recognizer.supportsOnDeviceRecognition)")

        // Captured once, here, so every result the task ever delivers carries
        // the turn it belongs to, whatever `turn` reads by the time it runs.
        let turn = self.turn
        task = recognizer.recognitionTask(with: request) {
            @Sendable [weak self] result, error in
            // Read what is needed here, on the callback's own thread, and send
            // only scalars across. `SFSpeechRecognitionResult` is not
            // Sendable, so handing the object itself to the main actor is a
            // data race the compiler refuses, and reaching back into it from
            // the other side would be one it cannot see. The error's code
            // goes too: it is the one thing that tells a person who said
            // nothing apart from a recogniser that was not running.
            let failed = error != nil
            let code = (error as NSError?)?.code ?? 0
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                self?.received(
                    text: text, isFinal: isFinal, failed: failed, errorCode: code, turn: turn)
            }
        }
    }

    /// Every recognition result lands here, on the main actor, as scalars.
    private func received(
        text: String?, isFinal: Bool, failed: Bool, errorCode: Int = 0, turn: Int
    ) {
        // A cancelled task reports an error, and this is where that error, and
        // every late result from a torn-down turn, is dropped on the floor.
        guard turn == self.turn else { return }
        if failed {
            if mode == .wake { restartIfWaking(); return }
            // Push to talk: the task is dead either way, and a partial in hand
            // is worth more than an error nobody can act on. On this Mac this
            // is the branch that commits nearly every sentence: the
            // recogniser answers `endAudio` with error 1101, never a final.
            logTurn("error", code: errorCode)
            if latestPartial.isEmpty {
                onSignal?(.failed(Self.message(forRecognizerError: errorCode)))
                stop()
            } else {
                commit(latestPartial)
            }
            return
        }
        guard let text else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isFinal {
            if mode == .wake {
                fire(text)
                restartIfWaking()
            } else {
                // A final with no words in it is the recogniser giving up,
                // not the person saying nothing. The last partial is the
                // sentence. `lag_ms=held` in the log means the recogniser
                // ended the turn under the key, which reads as "it stopped
                // listening to me" and is worth knowing the rate of.
                logTurn(trimmed.isEmpty ? "empty-final" : "final")
                commit(trimmed.isEmpty ? latestPartial : text)
            }
            return
        }
        // An empty revision never erases what was heard; a later one with
        // words in it replaces it.
        guard !trimmed.isEmpty else { return }
        latestPartial = text
        // In wake mode the room's conversation is a partial too. Show only what
        // follows the wake word, or the glass narrates other people's sentences.
        if mode == .wake {
            if let addressed = strippingWakeWord(from: text) { onSignal?(.partial(addressed)) }
        } else {
            onSignal?(.partial(text))
        }
        // Speech has no full stops. A pause is the only end-of-turn signal
        // there is, so the timer is the turn-taking model: reset it on every
        // partial, and when it finally fires the person has stopped talking.
        armSilence(text)
    }

    /// Close the turn on this text. The final and the grace timer both come
    /// here, and `stop()` bumping `turn` is what makes the second arrival
    /// inert. The app sees `.heard` and then `.listening(false)`, in that
    /// order, and main.swift leans on it to hold the transcript through the
    /// not-listening that follows.
    private func commit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onSignal?(.failed("Did not catch that"))
        } else {
            fire(trimmed)
        }
        stop()
    }

    private func armCommit() {
        let turn = self.turn
        commitTimer?.invalidate()
        commitTimer = Timer.scheduledTimer(withTimeInterval: commitGrace, repeats: false) {
            @Sendable _ in
            Task { @MainActor in self.commitLatestPartial(turn: turn) }
        }
    }

    /// The grace timer's body: commit what was heard, unless the turn has
    /// already closed or never produced a partial.
    private func commitLatestPartial(turn: Int) {
        guard turn == self.turn, !latestPartial.isEmpty else { return }
        logTurn("grace")
        commit(latestPartial)
    }

    /// See `finalFloor`. Armed beside the grace rather than instead of it: a
    /// turn with no partial has nothing for the grace to commit and is still
    /// waiting on a final, and this is what ends that wait.
    private func armFinalFloor() {
        let turn = self.turn
        finalTimeout?.invalidate()
        finalTimeout = Timer.scheduledTimer(withTimeInterval: Self.finalFloor, repeats: false) {
            @Sendable _ in
            Task { @MainActor in
                guard self.turn == turn, self.task != nil else { return }
                self.logTurn("floor")
                self.onSignal?(.failed("Did not catch that"))
                self.stop()
            }
        }
    }

    /// Milliseconds since the key came up, or nil while it is still down.
    private var lagSinceRelease: Int? {
        releasedAt.map { Int(Date().timeIntervalSince($0) * 1000) }
    }

    /// One line per turn end, written to disk. Notice rather than info
    /// because info is kept in memory only, which is how six failed presses
    /// on 2026-09-19 left nothing for `log show` to find.
    private func logTurn(_ source: String, code: Int = 0) {
        let lag = lagSinceRelease.map(String.init) ?? "held"
        Self.log.notice(
            "voice.turn source=\(source, privacy: .public) code=\(code) lag_ms=\(lag, privacy: .public) partial_chars=\(self.latestPartial.count)"
        )
    }

    /// What goes on the pill when the recogniser ends a turn with an error
    /// and nothing in hand. 1110 is its "no speech detected", which is the
    /// person's silence and reads as such. Anything else is the recogniser's
    /// own failure and must not be worded as the person's: six presses on
    /// 2026-09-19 came back 1101 because the on-device model could not be
    /// locked, and "Did not catch that" had the person speaking louder at a
    /// recogniser that was not running.
    static func message(forRecognizerError code: Int) -> String {
        switch code {
        case 0, 1110: return "Did not catch that"
        case 1101: return "Speech model not ready (1101). Try again."
        default: return "Speech recogniser failed (\(code)). Try again."
        }
    }

    private func stop(quiet: Bool = false) {
        // First, so every callback and timer still in flight for this turn
        // finds a mismatch and drops itself, including the error the cancel
        // below sends back through the recognition callback.
        turn += 1
        latestPartial = ""
        releasedAt = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        commitTimer?.invalidate()
        commitTimer = nil
        finalTimeout?.invalidate()
        finalTimeout = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        if !quiet {
            onSignal?(.listening(false))
            onSignal?(.level(0))
        }
    }

    private func restartIfWaking() {
        // Reopening the recogniser is not the same as the person stopping
        // talking, so the ring is left alone here: reporting `listening(false)`
        // between every utterance made it blink back to dormant several times a
        // minute while it was, in fact, still listening.
        let wasWaking = mode == .wake
        stop(quiet: wasWaking)
        guard mode == .wake else { return }
        // A short gap before reopening, or a recogniser that errored in a loop
        // spins the CPU as fast as it can fail.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if self.mode == .wake { self.start() }
        }
    }

    /// End the turn on a pause. Wake mode only, and that restriction is the
    /// whole point of push to talk.
    ///
    /// A silence timer is a guess about whether somebody has finished talking,
    /// and 1.1s is shorter than an ordinary pause for thought. While the key
    /// was held, pausing mid-sentence fired the half-sentence as a request and
    /// the rest of the sentence became a second one, so holding the key bought
    /// nothing: it behaved as though it were endpointing anyway.
    ///
    /// When the person is holding a key, the key IS the endpoint. There is no
    /// guess to make, so this does not run and `endPush` closes the turn.
    private func armSilence(_ text: String) {
        guard mode == .wake else { return }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) {
            @Sendable _ in
            Task { @MainActor in self.fire(text) }
        }
    }

    /// How long the same words count as one utterance being refined rather than
    /// as a second request. The recogniser settles well inside this.
    private static let repeatWindow: TimeInterval = 4

    private func fire(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let repeated = text == lastFired
            && Date().timeIntervalSince(lastFiredAt) < Self.repeatWindow
        guard !repeated else { return }

        if mode == .wake {
            guard let stripped = strippingWakeWord(from: text) else { return }
            lastFired = text
            lastFiredAt = Date()
            onSignal?(.heard(stripped))
        } else {
            lastFired = text
            lastFiredAt = Date()
            onSignal?(.heard(text))
        }
    }

    // MARK: Seams for tests
    //
    // The recogniser cannot be driven from a test, so the pieces of logic worth
    // testing are reachable directly: what counts as a repeat, what the wake
    // word strips, and what one turn does with its partials, its final and its
    // grace timer.

    func fireForTesting(_ text: String) { fire(text) }

    func expireRepeatWindowForTesting() {
        lastFiredAt = lastFiredAt.addingTimeInterval(-Self.repeatWindow - 1)
    }

    /// What the recognition callback does with this result. Returns the turn it
    /// was delivered to, which a test hands back to play the late arrivals a
    /// real turn produces: a final after the grace already committed, a partial
    /// after a cancel.
    @discardableResult
    func receivedForTesting(
        _ text: String?, isFinal: Bool, failed: Bool = false, errorCode: Int = 0,
        turn: Int? = nil
    ) -> Int {
        let turn = turn ?? self.turn
        received(text: text, isFinal: isFinal, failed: failed, errorCode: errorCode, turn: turn)
        return turn
    }

    /// Runs the commit timer's body now rather than waiting on the run loop,
    /// for the turn it would have been armed in.
    func fireCommitForTesting(turn: Int? = nil) {
        commitLatestPartial(turn: turn ?? self.turn)
    }

    /// Remove the wake word and everything before it, or return nil if it was
    /// never said.
    ///
    /// Everything before the wake word is discarded rather than kept, because in
    /// wake mode the audio before it is somebody's unrelated conversation.
    func strippingWakeWord(from text: String) -> String? {
        let lower = text.lowercased()
        // The earliest match across all the wake words, because two of them can
        // both appear and the first one is where the address begins.
        let best = wakeWords
            .compactMap { lower.range(of: $0) }
            .min { $0.lowerBound < $1.lowerBound }
        guard let best else { return nil }
        let after = text[best.upperBound...]
        let cleaned = after
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { $0 == "," || $0 == "." || $0 == "?" || $0 == "!" }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : String(cleaned)
    }

    /// Root mean square of a buffer, mapped to something a ring can use.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Double? {
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return nil }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = (sum / Float(count)).squareRoot()
        // Speech sits far below full scale, so a linear map spends its whole
        // range on the bottom tenth. This is a rough decibel curve chosen to put
        // ordinary talking in the middle of the ring's travel.
        let db = 20 * log10(max(rms, 1e-7))
        return min(max((Double(db) + 50) / 40, 0), 1)
    }
}
