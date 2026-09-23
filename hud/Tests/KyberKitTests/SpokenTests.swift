import Foundation
import Testing

@testable import KyberKit

@Suite("Spoken punctuation")
struct SpokenPunctuationTests {
    @Test("the words people say as punctuation become punctuation")
    func marks() {
        #expect(Spoken.punctuate("are you free question mark") == "are you free?")
        #expect(
            Spoken.punctuate("that is wild exclamation point") == "that is wild!")
        #expect(Spoken.punctuate("on my way period") == "on my way.")
        #expect(Spoken.punctuate("see you soon comma") == "see you soon,")
    }

    @Test("a mark mid-sentence keeps its space")
    func spacing() {
        #expect(
            Spoken.punctuate("are you free question mark I can come by")
                == "are you free? I can come by")
    }

    @Test("a new line is a new line")
    func lines() {
        #expect(Spoken.punctuate("dear sam new paragraph thanks") == "dear sam\n\nthanks")
        #expect(Spoken.punctuate("milk new line eggs") == "milk\neggs")
    }

    @Test("a sentence about a period is left alone")
    func prose() {
        // The rule this pins: a single punctuation word only counts as the last
        // word of the utterance. Firing mid-sentence turned "a period of time"
        // into "a. of time", which destroys a sentence to save a full stop.
        #expect(Spoken.punctuate("it was a period of time") == "it was a period of time")
        #expect(Spoken.punctuate("put a colon in the query") == "put a colon in the query")
        #expect(
            Spoken.punctuate("the comma goes after the name")
                == "the comma goes after the name")
    }

    @Test("nothing said is nothing written")
    func empty() {
        #expect(Spoken.punctuate("   ").isEmpty)
        #expect(Spoken.punctuate("").isEmpty)
    }
}
