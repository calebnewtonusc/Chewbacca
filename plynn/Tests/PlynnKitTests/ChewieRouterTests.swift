import XCTest

@testable import PlynnKit

final class ChewieRouterTests: XCTestCase {

    // MARK: - Wake word

    func testPlainDictationIsNotRouted() {
        XCTAssertNil(ChewieRouter.prompt(from: "send the deck to maggie tomorrow"))
        XCTAssertNil(ChewieRouter.prompt(from: ""))
        XCTAssertNil(ChewieRouter.prompt(from: "   "))
    }

    func testWakeWordIsStripped() {
        XCTAssertEqual(
            ChewieRouter.prompt(from: "Chewie, make a note with the texts I need to answer"),
            "make a note with the texts I need to answer")
        XCTAssertEqual(
            ChewieRouter.prompt(from: "Chewbacca what is due this week"),
            "what is due this week")
    }

    /// A speech recogniser will not spell the name the same way twice, and a
    /// wake word that only fires on the correct spelling does not fire.
    func testMisheardSpellingsStillWake() {
        for heard in ["chewy", "Chubaka", "chewbaca", "CHUBACCA"] {
            XCTAssertEqual(
                ChewieRouter.prompt(from: "\(heard): open the door"), "open the door",
                "\(heard) should have woken the router")
        }
    }

    func testLeadingPunctuationIsDropped() {
        XCTAssertEqual(ChewieRouter.prompt(from: "Chewie -- do the thing"), "do the thing")
        XCTAssertEqual(ChewieRouter.prompt(from: "Chewie... do the thing"), "do the thing")
    }

    /// Saying the name alone is someone testing the microphone. Pasting it is
    /// the right answer, and a twenty second agent round trip is not.
    func testBareWakeWordDoesNotRoute() {
        XCTAssertNil(ChewieRouter.prompt(from: "Chewie"))
        XCTAssertNil(ChewieRouter.prompt(from: "chewbacca."))
    }

    /// The word has to open the sentence. Dictating a sentence that mentions
    /// him must still paste as text.
    func testWakeWordMustBeFirst() {
        XCTAssertNil(ChewieRouter.prompt(from: "tell Chewie I said hello"))
        XCTAssertNil(ChewieRouter.prompt(from: "my dog is called Chewie"))
    }

    /// The wake word has to end where it ends. "Chewy's bowl is empty" matched
    /// the prefix, the apostrophe survived the punctuation trim, and a sentence
    /// about a dog was sent to an agent instead of being typed.
    func testWordsThatMerelyStartWithTheWakeWordDoNotRoute() {
        XCTAssertNil(ChewieRouter.prompt(from: "Chewy's bowl is empty"))
        XCTAssertNil(ChewieRouter.prompt(from: "chewbaccas are fictional"))
        XCTAssertNil(ChewieRouter.prompt(from: "Chewieness is not a word"))
    }

    /// ...while a real separator still wakes it.
    func testSeparatorsAfterTheWakeWordStillRoute() {
        for opener in ["Chewie ", "Chewie, ", "Chewie: ", "Chewie- ", "Chewie\n"] {
            XCTAssertEqual(
                ChewieRouter.prompt(from: opener + "open the door"), "open the door",
                "\(opener.debugDescription) should have woken the router")
        }
    }

    // MARK: - Selection as context

    /// "Chewie, make this shorter" is meaningless without the thing being
    /// pointed at, so a live selection travels with the request.
    func testSelectionIsAttachedToThePrompt() {
        let composed = ChewieRouter.compose(
            prompt: "make this shorter", selection: "The quarterly report is attached herewith.")
        XCTAssertTrue(composed.hasPrefix("make this shorter"))
        XCTAssertTrue(composed.contains("The quarterly report is attached herewith."))
    }

    func testNoSelectionLeavesThePromptAlone() {
        XCTAssertEqual(ChewieRouter.compose(prompt: "what is due", selection: nil), "what is due")
        XCTAssertEqual(ChewieRouter.compose(prompt: "what is due", selection: "   "), "what is due")
    }

    // MARK: - Local fallback

    /// The on-device model has no tools, and a fallback that invents a contact
    /// or a deadline is worse than one that admits it cannot look.
    func testLocalFallbackPromptForbidsGuessingAndCarriesTheRequest() {
        let p = ChewieRouter.localFallbackPrompt("how many texts do I owe")
        XCTAssertTrue(p.contains("how many texts do I owe"))
        XCTAssertTrue(p.contains("NO tools"))
        XCTAssertTrue(p.lowercased().contains("never guess"))
    }

    // MARK: - Opener stripping

    func testPrayerOpenerIsRemoved() {
        let reply = "Lord Jesus, thank You for this work. Amen.\n\nNoted 4 unanswered texts."
        XCTAssertEqual(ChewieRouter.stripOpener(reply), "Noted 4 unanswered texts.")
    }

    func testAnswerWithoutAnOpenerIsUntouched() {
        XCTAssertEqual(ChewieRouter.stripOpener("Noted 4 texts."), "Noted 4 texts.")
    }

    /// A one-paragraph reply that happens to be the opener is not stripped to
    /// nothing: an empty paste is worse than a strange one.
    func testOpenerOnlyReplyIsKept() {
        let onlyPrayer = "Father, be with him. Amen."
        XCTAssertEqual(ChewieRouter.stripOpener(onlyPrayer), onlyPrayer)
    }

    func testStrippingSurvivesTrailingPunctuationAndEmphasis() {
        let reply = "**Thank You, Lord. Amen.**\n\nDone."
        XCTAssertEqual(ChewieRouter.stripOpener(reply), "Done.")
    }

    /// A real answer whose first paragraph merely contains the word must
    /// survive. Only a paragraph ENDING in the word is an opener.
    func testParagraphMentioningAmenIsNotAnOpener() {
        let reply = "The word amen means so be it.\n\nThat is the whole answer."
        XCTAssertEqual(ChewieRouter.stripOpener(reply), reply)
    }

    // MARK: - Local vs Claude

    /// The whole point: saying hello should not cost twenty seconds.
    func testSmallTalkIsAnsweredLocally() {
        for q in ["hello", "what's up", "hey there", "thanks", "how are you"] {
            XCTAssertTrue(ChewieRouter.isLocallyAnswerable(q), "\(q) should stay local")
        }
    }

    func testGeneralKnowledgeIsAnsweredLocally() {
        XCTAssertTrue(ChewieRouter.isLocallyAnswerable("how many feet in a mile"))
        XCTAssertTrue(ChewieRouter.isLocallyAnswerable("what does ubiquitous mean"))
    }

    /// A capitalised proper noun escalates even when the question is plainly
    /// general knowledge. That costs twenty seconds on a trivia question, and
    /// it buys never inventing a fact about somebody the user actually knows.
    /// Of the two ways to be wrong, this is the recoverable one.
    func testProperNounsEscalateEvenForTrivia() {
        XCTAssertFalse(ChewieRouter.isLocallyAnswerable("what is the capital of France"))
        XCTAssertFalse(ChewieRouter.isLocallyAnswerable("who is Maggie"))
    }

    /// Anything about the user's own world must reach the real tools. A local
    /// answer here is not slower, it is invented.
    func testAnythingPersonalGoesToClaude() {
        for q in [
            "what did maggie say about the trip",
            "how many texts do I owe",
            "add a note that langston called",
            "what is due this week",
            "send him the deck",
            "open my calendar",
            "remind me to call mom",
        ] {
            XCTAssertFalse(ChewieRouter.isLocallyAnswerable(q), "\(q) must go to Claude")
        }
    }

    /// Long requests are never small talk.
    func testLongRequestsGoToClaude() {
        let long = String(repeating: "word ", count: 20)
        XCTAssertFalse(ChewieRouter.isLocallyAnswerable(long))
    }
}
