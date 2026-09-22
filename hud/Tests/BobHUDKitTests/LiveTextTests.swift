import AVFoundation
import Foundation
import Testing

@testable import BobHUDKit

@Suite("Live dictation text")
struct LiveTextTests {
    @Test("the newest word is never stable")
    func newestWordWaits() {
        let stable = LiveText.stablePrefix(
            previous: ["send", "me", "the"], current: ["send", "me", "the", "deck"])
        #expect(stable == ["send", "me", "the"])
        #expect(LiveText.stablePrefix(previous: [], current: ["send"]).isEmpty)
        #expect(LiveText.stablePrefix(previous: ["send"], current: ["send"]).isEmpty)
    }

    @Test("a revised word stops the stable run where it changed")
    func revisionStopsRun() {
        let stable = LiveText.stablePrefix(
            previous: ["text", "sara", "about"], current: ["text", "Sarah", "about", "it"])
        #expect(stable == ["text"])
    }

    @Test("an edit deletes only the tail that differs")
    func editIsMinimal() {
        let edit = LiveText.edit(from: "Hey Sagar", to: "Hey Sagar, can you")
        #expect(edit.delete == 0)
        #expect(edit.insert == ", can you")
        let fix = LiveText.edit(from: "deck for Northwynd", to: "deck for Northwind.")
        #expect(fix.delete == 3)
        #expect(fix.insert == "yra.")
        #expect(LiveText.edit(from: "same", to: "same") == (0, ""))
    }

    @Test("a turn's audio comes out as 16kHz mono WAV")
    func recorderWritesWav() throws {
        let format = try #require(
            AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
        buffer.frameLength = 4_800
        let recorder = AudioRecorder()
        recorder.append(buffer)
        recorder.append(buffer)
        let wav = try #require(recorder.wav16k())
        #expect(String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF")
        // 0.2s at 16kHz, 2 bytes a sample, plus the 44-byte header.
        #expect(abs(wav.count - (44 + 3_200 * 2)) < 400)
    }
}
