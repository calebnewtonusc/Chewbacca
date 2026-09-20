import AVFoundation

/// A short tone at the moment the press is heard.
///
/// The key came up, the words are in, and the answer is on its way. The pill
/// shows the same thing, but the person's eyes are on their work rather
/// than on the bottom edge, and the sound is what tells them they can stop
/// holding their breath. On 2026-09-20 the first spoken word landed 1.0s
/// after the prompt under the lean profile; a tone at 0s is the difference
/// between a second of silence and a second of waiting.
///
/// 40ms of 880Hz with 5ms ramps: short enough to be over before the first
/// spoken word, high enough that a laptop speaker plays it as a tone and
/// not a click, ramped so the edges do not click either. Guessed against the
/// ear, never measured.
///
/// Off by default since 2026-09-20, opt-in from the menu ("Sound when
/// heard"): a day of use said the release tone was one sound too many on
/// every sentence. See `earconOn` in main.swift.
@MainActor
public final class Earcon {
    nonisolated public static let frequency = 880.0
    nonisolated public static let duration = 0.04
    nonisolated public static let ramp = 0.005
    nonisolated public static let sampleRate = 44_100.0
    /// Quiet. The voice follows at full level and this is a tap on the
    /// shoulder, not a doorbell.
    nonisolated public static let gain: Float = 0.18

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?

    public init() {}

    /// The tone's samples: a sine with linear ramps in and out.
    nonisolated public static func samples(
        frequency: Double = frequency,
        duration: Double = duration,
        ramp: Double = ramp,
        sampleRate: Double = sampleRate
    ) -> [Float] {
        let count = Int(duration * sampleRate)
        let edge = max(1, Int(ramp * sampleRate))
        return (0..<count).map { index in
            let rising = min(1.0, Double(index) / Double(edge))
            let falling = min(1.0, Double(count - 1 - index) / Double(edge))
            let wave = sin(2 * .pi * frequency * Double(index) / sampleRate)
            return Float(wave * min(rising, falling)) * gain
        }
    }

    public func play() {
        if buffer == nil { prepare() }
        guard let buffer else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    private func prepare() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
        else { return }
        let samples = Self.samples()
        guard let made = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = made.floatChannelData
        else { return }
        made.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel[0].update(from: base, count: samples.count)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        buffer = made
    }
}
