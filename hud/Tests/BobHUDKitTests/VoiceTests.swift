import AppKit
import Foundation
import Testing

@testable import BobHUDKit

@Suite struct VocabularyTests {
    @Test func namesFirstThenFullNamesDeduplicated() {
        let words = Vocabulary.words(from: "Caleb Newton\ncaleb newton\n# a comment\n\n  Sarah Chen  \nCaleb\n")
        #expect(words.prefix(3) == ["Chewbacca", "Chewie", "Chewy"])
        #expect(Array(words.dropFirst(3)) == ["Caleb", "Sarah", "Caleb Newton", "Sarah Chen"])
    }

    @Test func capCutsTheList() {
        let text = (1...50).map { "Person\($0) Surname\($0)" }.joined(separator: "\n")
        let words = Vocabulary.words(from: text, cap: 10)
        #expect(words.count == 10)
        #expect(words[3] == "Person1")
    }

    @Test func emptyAndSingleLettersGiveOnlyTheOwnNames() {
        #expect(Vocabulary.words(from: "") == Vocabulary.own)
        #expect(Vocabulary.words(from: "a\n \nb") == Vocabulary.own)
    }
}

@Suite struct PushKeyTests {
    @Test func globeReadsItsOwnKeyCodeOnly() {
        #expect(PushKey.globe.state(keyCode: 63, flags: [.function]) == true)
        #expect(PushKey.globe.state(keyCode: 63, flags: []) == false, "the globe key came up")
        // Was `== false`, which is what broke it. Reporting "the talk key is
        // up" for somebody pressing Shift put 200 releases against 66 presses
        // into three hours of log on 2026-09-21, and the stateful double-tap
        // detector in front of `beginPush` read hold, stray release, stray
        // press as the exit gesture: 18 times, each shutting the microphone
        // 100ms after it opened. The turn then ended code=1110 with zero
        // partials and the pill said "Did not catch that".
        #expect(PushKey.globe.state(keyCode: 56, flags: [.shift]) == nil, "left Shift is not the talk key")
        #expect(PushKey.globe.state(keyCode: 58, flags: [.option, .function]) == nil,
                "a foreign key carrying the function flag is still not the talk key")
    }

    @Test func flagsAloneCanOnlyCloseATurn() {
        // The failsafe the old behaviour was reaching for, kept as its own
        // question so it cannot open a turn or reach the tap detector.
        #expect(PushKey.globe.heldByFlags([.function]))
        #expect(!PushKey.globe.heldByFlags([.shift]))
        #expect(PushKey.rightOption.heldByFlags([.option]))
        #expect(!PushKey.rightOption.heldByFlags([]))
    }

    @Test func rightModifiersReadTheirOwnKeyCodeOnly() {
        #expect(PushKey.rightOption.state(keyCode: 61, flags: [.option]) == true)
        #expect(PushKey.rightOption.state(keyCode: 61, flags: []) == false)
        #expect(PushKey.rightOption.state(keyCode: 58, flags: [.option]) == nil, "the left Option key is not the talk key")
        #expect(PushKey.rightCommand.state(keyCode: 54, flags: [.command]) == true)
        #expect(PushKey.rightControl.state(keyCode: 62, flags: [.control]) == true)
        #expect(PushKey.rightControl.state(keyCode: 62, flags: [.control, .shift]) == true)
    }

    @Test func everyKeyHasATitleAndALabel() {
        for key in PushKey.allCases {
            #expect(key.title.hasPrefix("the "))
            #expect(!key.label.isEmpty)
            #expect(PushKey(rawValue: key.rawValue) == key)
        }
    }
}

@Suite struct EarconTests {
    @Test func toneIsShortRampedAndQuiet() {
        let samples = Earcon.samples()
        #expect(samples.count == Int(Earcon.duration * Earcon.sampleRate))
        #expect(samples.first == 0)
        #expect(abs(samples.last ?? 1) < 0.001)
        let peak = samples.map { abs($0) }.max() ?? 0
        #expect(peak <= Earcon.gain && peak > Earcon.gain * 0.9)
        // The ramp is a ramp: the loudest sample is nowhere near the edges.
        let edge = Int(Earcon.ramp * Earcon.sampleRate)
        #expect(samples.prefix(edge).allSatisfy { abs($0) < Earcon.gain })
    }
}
