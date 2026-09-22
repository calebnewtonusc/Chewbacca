import AVFoundation
import Foundation

/// Keeps the microphone's audio for one dictation turn, so Whisper can read the
/// whole sentence again once the person stops.
///
/// Filled on the realtime audio thread from the listener's tap and read once on
/// the main actor afterwards. The lock is the only thing shared, which is why
/// `@unchecked Sendable` is honest here.
public final class AudioRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var frames: AVAudioFrameCount = 0

    /// Two minutes at 48kHz. Past that the recogniser has long since ended the
    /// turn on its own, so anything more is a tap nobody closed. Guessed,
    /// never hit.
    private static let maxFrames: AVAudioFrameCount = 48_000 * 120

    public init() {}

    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = Self.copy(buffer) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard frames + copy.frameLength <= Self.maxFrames else { return }
        buffers.append(copy)
        frames += copy.frameLength
    }

    /// The turn as 16kHz mono 16-bit WAV, which is what whisper.cpp reads
    /// without ffmpeg.
    public func wav16k() -> Data? {
        lock.lock()
        let buffers = self.buffers
        let frames = self.frames
        lock.unlock()
        guard let first = buffers.first, frames > 0,
              let target = AVAudioFormat(
                  commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1,
                  interleaved: true),
              let converter = AVAudioConverter(from: first.format, to: target)
        else { return nil }
        converter.downmix = true
        let capacity = AVAudioFrameCount(
            Double(frames) * 16_000 / first.format.sampleRate) + 4_096
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
        else { return nil }
        var index = 0
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in
            guard index < buffers.count else {
                status.pointee = .endOfStream
                return nil
            }
            status.pointee = .haveData
            index += 1
            return buffers[index - 1]
        }
        guard error == nil, out.frameLength > 0, let samples = out.int16ChannelData
        else { return nil }
        let pcm = Data(bytes: samples[0], count: Int(out.frameLength) * 2)
        return Self.wavHeader(bytes: pcm.count) + pcm
    }

    /// The tap hands over a buffer it may reuse, so the samples are copied out.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
              let from = buffer.floatChannelData, let to = copy.floatChannelData
        else { return nil }
        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let stride = buffer.format.isInterleaved ? channels : 1
        let count = Int(buffer.frameLength) * stride
        for channel in 0..<(buffer.format.isInterleaved ? 1 : channels) {
            to[channel].update(from: from[channel], count: count)
        }
        return copy
    }

    private static func wavHeader(bytes: Int) -> Data {
        var header = Data()
        func append(_ text: String) { header.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) } }
        append("RIFF")
        append32(UInt32(36 + bytes))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)  // PCM
        append16(1)  // mono
        append32(16_000)
        append32(32_000)  // byte rate
        append16(2)  // block align
        append16(16)
        append("data")
        append32(UInt32(bytes))
        return header
    }
}
