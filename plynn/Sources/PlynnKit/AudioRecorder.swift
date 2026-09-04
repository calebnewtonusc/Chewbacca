import AVFoundation

public enum AudioLevel {
    /// Root-mean-square level of a sample chunk (0 for empty input).
    public static func rms(of samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }

    /// RMS of each fixed-size window across the chunk.
    ///
    /// One value per audio callback moves the meter at buffer rate (~12 Hz),
    /// which reads as laggy no matter how it's drawn. Slicing the same chunk
    /// into short windows yields several envelope points per callback, so the
    /// visualiser can run at UI rate off audio that already arrived.
    public static func envelope(of samples: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 0, !samples.isEmpty else { return [] }
        var points: [Float] = []
        points.reserveCapacity(samples.count / windowSize + 1)
        var start = 0
        while start < samples.count {
            let end = min(start + windowSize, samples.count)
            var sum: Float = 0
            for i in start..<end { sum += samples[i] * samples[i] }
            points.append((sum / Float(end - start)).squareRoot())
            start = end
        }
        return points
    }

    /// Perceptual 0…1 from a raw RMS.
    ///
    /// Speech lands roughly between −50 and −10 dBFS, and loudness is
    /// logarithmic — scaling raw amplitude linearly leaves normal talking
    /// hugging the floor and shouting pinned at the ceiling. Mapping the dB
    /// range instead keeps the whole span of a voice visible.
    public static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let floor: Float = -50
        let ceiling: Float = -10
        return min(1, max(0, (db - floor) / (ceiling - floor)))
    }
}

public enum AudioError: Error {
    /// The input device reported no usable format — typically another app
    /// (FaceTime, Zoom) is mid-reconfiguring the shared device.
    case noInputFormat
}

/// Taps the default input device, converts to 16 kHz mono Float32.
/// start() spins up the engine; stop() tears it down and returns all samples.
///
/// When another app engages voice processing on the shared input (FaceTime,
/// Zoom), CoreAudio reconfigures the device and AVAudioEngine posts a
/// configuration-change notification that silently stops the running graph.
/// We observe it and re-arm the tap so capture survives the reconfiguration.
public final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let lock = NSLock()
    private var configObserver: NSObjectProtocol?

    /// Serialises every mutation of the engine graph.
    ///
    /// The configuration-change notification is posted with `queue: nil`, which
    /// means it is delivered on whichever thread CoreAudio happened to post it
    /// from, not the main one. That handler re-arms the tap while `stop()` may
    /// be tearing the same graph down from the main thread, and two threads
    /// inside AVAudioEngine's stop path is a null dereference in
    /// `AudioOutputUnitStop`. That is the 2026-09-02 segfault.
    private let graphLock = NSLock()

    /// False once `stop()` has run, so a configuration change that arrives
    /// during teardown does not resurrect the engine after the caller has
    /// already taken its samples and moved on.
    private var isCapturing = false

    /// Called on the audio tap thread with each converted 16 kHz chunk —
    /// feeds both the streaming transcriber and the UI level meter.
    public var onChunk: (([Float]) -> Void)?

    public init() {}

    public func start() throws {
        samples.removeAll(keepingCapacity: true)
        graphLock.lock()
        isCapturing = true
        graphLock.unlock()
        try armAndStart()
        // A device reconfiguration (another app grabbing/releasing the mic)
        // stops the engine without an error; rebuild the graph when it does.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            try? self.armAndStart()
        }
    }

    /// Install the tap for the current hardware format and (re)start the engine.
    /// Safe to call again after a configuration change, and safe to call while
    /// `stop()` is running on another thread.
    private func armAndStart() throws {
        graphLock.lock()
        defer { graphLock.unlock() }
        // A configuration change can land between stop() taking the lock and
        // the caller believing capture is over. Re-arming here would restart a
        // microphone the user thinks they switched off.
        guard isCapturing else { return }
        let input = engine.inputNode
        engine.stop()
        input.removeTap(onBus: 0)

        let inFmt = input.outputFormat(forBus: 0)
        // A contended/reconfiguring device reports 0 Hz or 0 channels; installing
        // a tap with that format throws deep in CoreAudio. Fail cleanly instead.
        guard inFmt.sampleRate > 0, inFmt.channelCount > 0 else {
            throw AudioError.noInputFormat
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: inFmt) { [weak self] buffer, _ in
            guard let self, let chunk = try? Resampler.convert(buffer: buffer, to: AudioFile.targetFormat)
            else { return }
            self.lock.lock(); self.samples.append(contentsOf: chunk); self.lock.unlock()
            self.onChunk?(chunk)
        }
        engine.prepare()
        try engine.start()
    }

    public func stop() -> [Float] {
        // Drop the observer first so no new re-arm can be scheduled, then take
        // the graph lock so any re-arm already in flight finishes before the
        // teardown starts. Doing it the other way round leaves a window where
        // both threads are inside AVAudioEngine at once.
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        graphLock.lock()
        isCapturing = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        graphLock.unlock()

        lock.lock(); defer { lock.unlock() }
        return samples
    }
}
