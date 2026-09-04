import AVFoundation
import Foundation
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

    public init() {}

    // MARK: Permission

    /// Ask once, and report honestly rather than failing silently.
    ///
    /// A denied microphone is the single most confusing failure this component
    /// can have, because everything else keeps working and the ring simply never
    /// moves. It has to say so.
    public func authorize(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                guard status == .authorized else {
                    self.onSignal?(.failed("Speech recognition not permitted"))
                    done(false)
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
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

    /// Held key went down. Only meaningful in push-to-talk.
    public func beginPush() {
        guard mode == .pushToTalk else { return }
        authorize { ok in if ok { self.start() } }
    }

    /// Held key came up.
    public func endPush() {
        guard mode == .pushToTalk else { return }
        finishUtterance()
        stop()
    }

    // MARK: Engine

    private func start() {
        guard task == nil else { return }
        guard let recognizer, recognizer.isAvailable else {
            onSignal?(.failed("Speech recogniser unavailable"))
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device or not at all. `requiresOnDeviceRecognition` is a request
        // rather than a guarantee on older hardware, so it is paired with the
        // availability check above and the mode stays opt-in.
        request.requiresOnDeviceRecognition = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
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

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if error != nil {
                    self.restartIfWaking()
                    return
                }
                guard let result else { return }
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.fire(text)
                    self.restartIfWaking()
                } else {
                    // Speech has no full stops. A pause is the only end-of-turn
                    // signal there is, so the timer is the turn-taking model:
                    // reset it on every partial, and when it finally fires the
                    // person has stopped talking.
                    self.armSilence(text)
                }
            }
        }
    }

    private func stop(quiet: Bool = false) {
        silenceTimer?.invalidate()
        silenceTimer = nil
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

    private func armSilence(_ text: String) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { _ in
            Task { @MainActor in self.fire(text) }
        }
    }

    private func finishUtterance() {
        silenceTimer?.invalidate()
        request?.endAudio()
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
    // The recogniser cannot be driven from a test, so the two pieces of logic
    // worth testing are reachable directly: what counts as a repeat, and what
    // the wake word strips.

    func fireForTesting(_ text: String) { fire(text) }

    func expireRepeatWindowForTesting() {
        lastFiredAt = lastFiredAt.addingTimeInterval(-Self.repeatWindow - 1)
    }

    /// Remove the wake word and everything before it, or return nil if it was
    /// never said.
    ///
    /// Everything before the wake word is discarded rather than kept, because in
    /// wake mode the audio before it is somebody's unrelated conversation.
    func strippingWakeWord(from text: String) -> String? {
        let lower = text.lowercased()
        var best: Range<String.Index>?
        for word in wakeWords {
            guard let found = lower.range(of: word) else { continue }
            if best == nil || found.lowerBound < best!.lowerBound { best = found }
        }
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
