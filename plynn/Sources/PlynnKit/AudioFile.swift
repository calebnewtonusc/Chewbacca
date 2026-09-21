import AVFoundation

public enum AudioFile {
    // AVAudioFormat picked up `Sendable` in the macOS 26 SDK and does not have
    // it in the 15 one, so under strict concurrency this static tripped
    // "non-Sendable type may have shared mutable state" on the older SDK only.
    // The value is constructed once from three constants and never mutated:
    // AVAudioFormat has no mutating API at all, which is exactly the case
    // `nonisolated(unsafe)` exists for. It is a statement about this value,
    // not a blanket opt-out.
    nonisolated(unsafe) public static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    /// Reads any audio file and returns 16 kHz mono Float32 samples.
    public static func loadSamples16kMono(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inBuf = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: inBuf)
        return try Resampler.convert(buffer: inBuf, to: targetFormat)
    }
}
