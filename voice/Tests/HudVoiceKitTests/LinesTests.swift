import Foundation
import Testing

@testable import HudVoiceKit

@Suite struct LinesTests {
    @Test func parsesTheBridgeProtocol() {
        #expect(Lines.parse(#"{"say": "Done.", "more": true}"#) == .say("Done.", more: true))
        #expect(Lines.parse(#"{"say": "Done."}"#) == .say("Done.", more: false))
        #expect(Lines.parse(#"{"add": "  And this. "}"#) == .add("And this."))
        #expect(Lines.parse(#"{"end": true}"#) == .end)
        #expect(Lines.parse(#"{"hush": true}"#) == .hush)
        #expect(Lines.parse(#"{"say": "   "}"#) == nil)
        #expect(Lines.parse("not json") == nil)
    }

    @Test func writesTheSameLinesOut() {
        #expect(Lines.level(0.616) == "{\"level\": 0.62}")
        #expect(Lines.level(7) == "{\"level\": 1.0}")
        #expect(Lines.saying("Two \"things\" tomorrow.") == "{\"saying\":\"Two \\\"things\\\" tomorrow.\"}")
        #expect(Lines.quiet == "{\"quiet\": true}")
        let data = Lines.status("Getting the voice ready").data(using: .utf8)!
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        #expect(object?["status"] == "Getting the voice ready")
    }

    @Test func splitsSentencesLikeHudSpeak() {
        let parts = Lines.sentences("Checking your calendar. You have three things tomorrow! Two are all day. Ok.")
        #expect(parts == ["Checking your calendar.", "You have three things tomorrow!", "Two are all day. Ok."])
        #expect(Lines.sentences("   ") == [])
        #expect(Lines.sentences("No end") == ["No end"])
        #expect(Lines.sentences("Dr. Who is here. Yes.") == ["Dr. Who is here. Yes."])
        #expect(Lines.sentences("Yes. That is the one you booked yesterday.") == ["Yes. That is the one you booked yesterday."])
        #expect(Lines.sentences("Yes.") == ["Yes."])
    }
}

@Suite struct EnvelopeTests {
    @Test func loudestFrameIsOneAndSilenceIsZero() {
        let rate = 24_000
        let width = Int(Double(rate) * Envelope.frame)
        var samples = [Float](repeating: 0, count: width * 3)
        for i in width..<(width * 2) { samples[i] = 0.5 }
        for i in (width * 2)..<(width * 3) { samples[i] = 0.25 }
        let levels = Envelope.of(samples, sampleRate: rate)
        #expect(levels.count == 3)
        #expect(levels[0] == 0)
        #expect(levels[1] == 1)
        #expect(abs(levels[2] - Float(pow(0.5, 0.7))) < 0.001)
        #expect(Envelope.of([Float](repeating: 0, count: width * 2), sampleRate: rate) == [0, 0])
        #expect(Envelope.of([], sampleRate: rate) == [])
    }
}
