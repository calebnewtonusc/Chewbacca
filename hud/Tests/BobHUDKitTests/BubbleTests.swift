import CoreGraphics
import Foundation
import Testing

@testable import BobHUDKit

@Suite("The dictation bubble, on the wire")
struct BubbleWireTests {
    @Test("`b` on its own spawns one where the display decides")
    func spawnsUnnamed() throws {
        let op = try #require(try LineParser.parse("b"))
        guard case .spawnBubble(let id) = op else {
            Issue.record("expected a spawn")
            return
        }
        #expect(id == nil)
    }

    @Test("`b <id>` spawns that one")
    func spawnsNamed() throws {
        let op = try #require(try LineParser.parse("b b2"))
        guard case .spawnBubble(let id) = op, id == "b2" else {
            Issue.record("expected a named spawn")
            return
        }
    }

    @Test("a centre point moves one, with a state and an app")
    func moves() throws {
        let op = try #require(
            try LineParser.parse(#"b b1 400 720 state=idle app="Messages""#))
        guard case .bubble(let id, let center, let state, let app, let note) = op else {
            Issue.record("expected a bubble op")
            return
        }
        #expect(id == "b1")
        #expect(center == CGPoint(x: 400, y: 720))
        #expect(state == .idle)
        #expect(app == "Messages")
        #expect(note == nil)
    }

    @Test("`off` takes one down and `clear` takes them all")
    func removes() throws {
        guard case .unbubble(let one)? = try LineParser.parse("b b1 off"),
              case .unbubble(let all)? = try LineParser.parse("b clear")
        else {
            Issue.record("expected two unbubble ops")
            return
        }
        #expect(one == "b1")
        #expect(all.isEmpty, "an empty id means every bubble")
    }

    @Test("insert carries a whole sentence, spaces and all")
    func insertsASentence() throws {
        let op = try #require(
            try LineParser.parse(#"b b1 insert "Running late, be there at six.""#))
        guard case .bubbleInsert(let id, let text) = op else {
            Issue.record("expected an insert")
            return
        }
        #expect(id == "b1")
        #expect(text == "Running late, be there at six.")
    }

    @Test("a state without a point is refused rather than placed at zero")
    func refusesHalfAMove() {
        // `b b1 400` is an id and one number. Placing it at 400,0 would put the
        // bubble in the menu bar, which is the kind of failure that looks like
        // a rendering bug for an hour before anybody reads the line.
        #expect(throws: (any Error).self) {
            _ = try LineParser.parse("b b1 400")
        }
    }

    @Test("the verb is announced, or nobody knows it is there")
    func announced() {
        // A client asks for the version to find out what it may send. `w` was
        // added to the parser and left out of this string for a week, so
        // anything reading the list believed the display could not take a
        // written answer.
        #expect(SocketServer.version.contains(",b,"))
    }

    @Test("what goes back up the socket")
    func outbound() {
        #expect(
            OutboundEvent.bubble(id: "b1", state: .idle, app: "Messages", note: nil).line
                == #"b b1 idle app="Messages""#)
        #expect(
            OutboundEvent.bubble(
                id: "b1", state: .unbound, app: nil, note: "no text field there").line
                == #"b b1 unbound note="no text field there""#)
        #expect(
            OutboundEvent.dictated(id: "b1", text: "on my way").line
                == #"b b1 said "on my way""#)
        #expect(
            OutboundEvent.clean(id: "b1", text: "on my way comma be there soon").line
                == #"b b1 clean "on my way comma be there soon""#)
    }

    @Test("every line the display sends about a bubble parses on the way back in")
    func roundTrips() throws {
        // The two directions are deliberately the same shape, and a listener
        // that echoed a state line back would otherwise crash the display's
        // parser rather than being ignored.
        for state in [
            BubbleState.unbound, .idle, .dimmed, .live, .thinking, .orphaned,
        ] {
            let line = OutboundEvent.bubble(
                id: "b1", state: state, app: "Mail", note: nil).line
            // The outbound form is `b <id> <state>`, which inbound reads as an
            // unknown third token rather than as coordinates, so it must not
            // throw and must not move anything.
            _ = try? LineParser.parse(line)
        }
    }
}

@Suite("The dictation bubble, on the glass")
@MainActor
struct BubbleModelTests {
    @Test("a spawned bubble is bound to nothing")
    func spawnsUnbound() {
        let model = OverlayModel()
        let bubble = model.spawnBubble()
        #expect(bubble.state == .unbound)
        #expect(!bubble.isBound)
        #expect(model.bubbles.count == 1)
        #expect(bubble.label == "drag me onto a text box")
    }

    @Test("names are handed out lowest first, and reused once freed")
    func names() {
        let model = OverlayModel()
        #expect(model.nextBubbleName() == "b1")
        model.spawnBubble()
        #expect(model.nextBubbleName() == "b2")
        model.spawnBubble()
        model.removeBubble("b1")
        #expect(model.nextBubbleName() == "b1")
    }

    @Test("three at once, and no more")
    func capped() {
        let model = OverlayModel()
        for _ in 0..<5 { model.spawnBubble() }
        #expect(model.bubbles.count == OverlayModel.maxBubbles)
    }

    @Test("moving one does not unbind it, because a drag is not a drop")
    func moveKeepsBinding() {
        let model = OverlayModel()
        model.spawnBubble(id: "b1")
        model.setBubble("b1", state: .idle, app: "Messages")
        model.moveBubble("b1", to: CGPoint(x: 10, y: 10))
        let bubble = model.bubbles[0]
        #expect(bubble.center == CGPoint(x: 10, y: 10))
        #expect(bubble.state == .idle)
    }

    @Test("the words are cleared by any state that is not listening")
    func heardIsPerTurn() {
        // The failure this prevents: a turn ends, the next click opens the
        // microphone, and the bubble is still showing the previous sentence, so
        // the person cannot tell whether it heard them.
        let model = OverlayModel()
        model.spawnBubble(id: "b1")
        model.setBubble("b1", state: .live)
        model.setBubbleHeard("b1", "running late")
        #expect(model.bubbles[0].heard == "running late")
        #expect(model.bubbles[0].label == "running late")
        model.setBubble("b1", state: .thinking)
        #expect(model.bubbles[0].heard.isEmpty)
    }

    @Test("a refusal note does not outlive the refusal")
    func noteClears() {
        let model = OverlayModel()
        model.spawnBubble(id: "b1")
        model.setBubble("b1", state: .unbound, note: "no text field there")
        #expect(model.bubbles[0].note == "no text field there")
        model.setBubble("b1", state: .idle, app: "Mail")
        #expect(model.bubbles[0].note == nil)
        #expect(model.bubbles[0].label == "dictate into Mail")
    }

    @Test("a click lands on the newest bubble in an overlap")
    func hitTestPrefersTheTopOne() {
        let model = OverlayModel()
        model.bubble(id: "under", center: CGPoint(x: 100, y: 100))
        model.bubble(id: "over", center: CGPoint(x: 104, y: 100))
        #expect(model.bubble(at: CGPoint(x: 102, y: 100))?.id == "over")
        #expect(model.bubble(at: CGPoint(x: 400, y: 400)) == nil)
    }

    @Test("the target is at least 44 points, though the circle is 34")
    func tapTarget() {
        let bubble = Bubble(id: "b1", center: CGPoint(x: 100, y: 100))
        #expect(bubble.frame.width == 34)
        #expect(bubble.hitFrame.width >= 44, "Fitts's law floor")
        // A press 20 points from the centre is on it; the drawn circle ends at
        // 17, and the difference is what stops a click at the edge missing.
        #expect(bubble.hitFrame.contains(CGPoint(x: 120, y: 100)))
    }

    @Test("bubbles are solid glass, or they cannot be dragged")
    func interactive() {
        // The window ignores the mouse everywhere it has not been told
        // something is drawn, so a bubble missing from `frames` is a bubble
        // that paints and does nothing. That was the first version.
        let model = OverlayModel()
        model.bubble(id: "b1", center: CGPoint(x: 100, y: 100))
        #expect(model.frames.contains { $0.contains(CGPoint(x: 100, y: 100)) })
    }

    @Test("hovering writes only on a change")
    func hoverIsCheap() {
        let model = OverlayModel()
        model.bubble(id: "b1", center: .zero)
        model.hoverBubble("b1")
        let after = model.revision
        model.hoverBubble("b1")
        #expect(model.revision == after, "every write invalidates a SwiftUI body")
    }

    @Test("the socket can spawn, move and clear")
    func throughTheParser() throws {
        let model = OverlayModel()
        model.apply(try #require(try LineParser.parse("b b1")))
        #expect(model.bubbles.count == 1)
        model.apply(try #require(try LineParser.parse("b b1 300 500 state=dimmed")))
        #expect(model.bubbles[0].center == CGPoint(x: 300, y: 500))
        #expect(model.bubbles[0].state == .dimmed)
        model.apply(try #require(try LineParser.parse("b clear")))
        #expect(model.bubbles.isEmpty)
    }

    @Test("an insert is not handed to a surface's data model")
    func insertIsNotData() throws {
        // `.bubbleInsert` is answered by the display, not the model. Without an
        // explicit case it fell through to `default`, which forwards to the
        // current surface's store, where it silently did nothing: the sentence
        // vanished and the bubble sat in `thinking` for ever.
        let model = OverlayModel()
        model.spawnBubble(id: "b1")
        let before = model.bubbles
        model.apply(try #require(try LineParser.parse(#"b b1 insert "hello""#)))
        #expect(model.bubbles == before)
    }
}

@Suite("Spoken punctuation")
struct BubblePunctuationTests {
    @Test("the words people say as punctuation become punctuation")
    func marks() {
        #expect(Bubble.punctuate("are you free question mark") == "are you free?")
        #expect(
            Bubble.punctuate("that is wild exclamation point") == "that is wild!")
        #expect(Bubble.punctuate("on my way period") == "on my way.")
        #expect(Bubble.punctuate("see you soon comma") == "see you soon,")
    }

    @Test("a mark mid-sentence keeps its space")
    func spacing() {
        #expect(
            Bubble.punctuate("are you free question mark I can come by")
                == "are you free? I can come by")
    }

    @Test("a new line is a new line")
    func lines() {
        #expect(Bubble.punctuate("dear sam new paragraph thanks") == "dear sam\n\nthanks")
        #expect(Bubble.punctuate("milk new line eggs") == "milk\neggs")
    }

    @Test("a sentence about a period is left alone")
    func prose() {
        // The rule this pins: a single punctuation word only counts as the last
        // word of the utterance. Firing mid-sentence turned "a period of time"
        // into "a. of time", which destroys a sentence to save a full stop.
        #expect(Bubble.punctuate("it was a period of time") == "it was a period of time")
        #expect(Bubble.punctuate("put a colon in the query") == "put a colon in the query")
        #expect(
            Bubble.punctuate("the comma goes after the name")
                == "the comma goes after the name")
    }

    @Test("nothing said is nothing written")
    func empty() {
        #expect(Bubble.punctuate("   ").isEmpty)
        #expect(Bubble.punctuate("").isEmpty)
    }
}
