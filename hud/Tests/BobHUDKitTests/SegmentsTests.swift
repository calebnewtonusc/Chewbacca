import AVFoundation
import Foundation
import Testing

@testable import BobHUDKit

@Suite struct SegmentsTests {
    @Test func aRestartAfterAPauseIsANewSegment() {
        #expect(Segments.isRestart(
            current: "I need to finish the essay tonight.", next: "and", closed: false))
        #expect(Segments.isRestart(
            current: "I need to finish the essay tonight.", next: "and then I", closed: false))
    }

    @Test func aRevisionIsNeverARestart() {
        // The same length with a word changed, which is what the recogniser
        // does to a partial many times a second.
        #expect(!Segments.isRestart(current: "Send the deck to", next: "Sent the deck", closed: false))
        #expect(!Segments.isRestart(current: "text sara", next: "Text Sarah", closed: false))
        #expect(!Segments.isRestart(current: "text sara", next: "Text Sarah", closed: true),
                "agreeing on the opening words beats the metadata")
        #expect(!Segments.isRestart(current: "send me the", next: "send me the deck", closed: false))
    }

    @Test func theMetadataCatchesARestartTheLengthRuleCannot() {
        // Four words after seven is too long to be sure of by length alone.
        let current = "I need to finish the essay tonight."
        #expect(!Segments.isRestart(current: current, next: "and then I will", closed: false))
        #expect(Segments.isRestart(current: current, next: "and then I will", closed: true))
        // The new segment can open on the same word as the old one.
        #expect(Segments.isRestart(current: current, next: "I will", closed: true))
        #expect(!Segments.isRestart(current: current, next: current + " and", closed: true),
                "a continuation past the boundary is not a restart")
    }

    @Test func nothingToRestartFrom() {
        #expect(!Segments.isRestart(current: "", next: "hello", closed: true))
    }

    @Test func joinNeverSaysAnythingTwice() {
        #expect(Segments.join("I need to finish the essay tonight.", "And then sleep.")
                == "I need to finish the essay tonight. And then sleep.")
        #expect(Segments.join("", "hello") == "hello")
        #expect(Segments.join("hello", "") == "hello")
        // A final that repeats the whole turn is taken as it is.
        #expect(Segments.join("I need to finish", "I need to finish the essay.")
                == "I need to finish the essay.")
    }

    // The 2026-09-22 turn, played through the listener: two segments and a
    // final that holds only the second.

    @Test("a pause mid-press keeps what came before it, live and at the end")
    @MainActor
    func stitchesSegmentsAcrossAPause() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var partials: [String] = []
        var heard: [String] = []
        voice.onSignal = { signal in
            switch signal {
            case .partial(let text): partials.append(text)
            case .heard(let text): heard.append(text)
            default: break
            }
        }
        let turn = voice.receivedForTesting("I need to finish", isFinal: false)
        voice.receivedForTesting(
            "I need to finish the essay tonight.", isFinal: false, segmentEnded: true, turn: turn)
        voice.receivedForTesting("and", isFinal: false, turn: turn)
        voice.receivedForTesting("and then sleep", isFinal: false, turn: turn)
        voice.receivedForTesting("And then sleep.", isFinal: true, turn: turn)
        #expect(partials.last == "I need to finish the essay tonight. and then sleep")
        #expect(partials.allSatisfy { $0.hasPrefix("I need to finish") },
                "no partial may drop the first sentence, or the typer deletes it")
        #expect(heard == ["I need to finish the essay tonight. And then sleep."])
    }

    @Test("the grace commits every segment, not just the open one")
    @MainActor
    func graceCommitsTheWholeTurn() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var heard: [String] = []
        voice.onSignal = { signal in
            if case .heard(let text) = signal { heard.append(text) }
        }
        let turn = voice.receivedForTesting("first sentence here done", isFinal: false)
        voice.receivedForTesting("second", isFinal: false, turn: turn)
        voice.fireCommitForTesting(turn: turn)
        #expect(heard == ["first sentence here done second"])
    }
}

@Suite struct WhisperCheckTests {
    @Test("the 2026-09-22 turn: Whisper heard the whole sentence and must win")
    func acceptsMoreThanTheRecogniserKept() {
        let typed = "and then I will send it."  // 24 characters, what was kept
        let heard = "I need to finish the essay for anthropology tonight and then I will send it to the group chat."
        #expect(Whisper.rejection(heard: heard, typed: typed, seconds: 11.7) == nil)
    }

    @Test func rejectsWhatTheAudioCannotHold() {
        let heard = (1...40).map { "word\($0)" }.joined(separator: " ")
        #expect(Whisper.rejection(heard: heard, typed: "hello there", seconds: 2) == "too_long")
    }

    @Test func rejectsARepeatingHallucination() {
        let heard = Array(repeating: "thank you for watching", count: 5).joined(separator: " ")
        #expect(Whisper.rejection(heard: heard, typed: "thank you", seconds: 30) == "repeating")
    }

    @Test func rejectsWhisperMissingMostOfIt() {
        #expect(Whisper.rejection(
            heard: "hello", typed: "hello there how are you doing today", seconds: 3) == "short")
        #expect(Whisper.rejection(heard: "  ", typed: "hello", seconds: 1) == "empty")
    }

    @Test func secondsOfSixteenKilohertzMonoWav() {
        // 374,444 bytes was the 2026-09-22 turn: 44 of header, then 2 bytes a
        // sample at 16kHz.
        #expect(abs(Whisper.seconds(ofWav: Data(count: 374_444)) - 11.7) < 0.01)
        #expect(Whisper.seconds(ofWav: Data(count: 10)) == 0)
    }
}

@Suite struct MicrophoneTests {
    /// A 3-channel buffer with one live channel, the shape the display read
    /// from 23:48 on 2026-09-22 while it heard nothing.
    static func buffer(channels: Int, live: [Int], value: Float = 0.25) -> AVAudioPCMBuffer {
        // Past two channels a format needs a layout, as the engine's own has.
        let layout = AVAudioChannelLayout(
            layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels))!
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channelLayout: layout)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256)!
        buffer.frameLength = 256
        for channel in 0..<channels {
            for index in 0..<256 {
                buffer.floatChannelData![channel][index] = live.contains(channel) ? value : 0
            }
        }
        return buffer
    }

    @Test func manyChannelsBecomeOneWithoutLosingTheLiveOne() throws {
        let mono = try #require(VoiceListener.mono(Self.buffer(channels: 3, live: [2])))
        #expect(mono.format.channelCount == 1)
        #expect(mono.frameLength == 256)
        #expect(mono.floatChannelData![0][10] == 0.25, "a silent channel must not dilute the live one")
    }

    @Test func monoIsLeftAlone() {
        #expect(VoiceListener.mono(Self.buffer(channels: 1, live: [0])) == nil)
    }

    @Test func digitalZeroIsSilenceAndRoomNoiseIsNot() {
        #expect(!VoiceListener.carriesSignal(Self.buffer(channels: 3, live: [])))
        #expect(VoiceListener.carriesSignal(Self.buffer(channels: 1, live: [0], value: 1e-4)),
                "a quiet room on a working microphone is still signal")
    }
}
