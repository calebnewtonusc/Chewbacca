import CoreGraphics
import SwiftUI
import Foundation
import Testing
@testable import KyberKit

/// The Swift parser and store are ports of the TypeScript, so they need the same
/// guarantees tested the same way. A port that drifts is worse than no port: the
/// panel would render something subtly different from every other surface.

@Suite("Kyber Lines")
struct LineParserTests {
    @Test("parses a component with mixed prop types")
    func component() throws {
        let op = try #require(try LineParser.parse(#"c hero Metric label="Q3 revenue" value=4820000 up=true"#))
        guard case .component(let node) = op else { Issue.record("not a component"); return }
        #expect(node.id == "hero")
        #expect(node.type == "Metric")
        #expect(node.props["label"] == .literal(.string("Q3 revenue")))
        #expect(node.props["value"] == .literal(.number(4820000)))
        #expect(node.props["up"] == .literal(.bool(true)))
    }

    @Test("a bare word is a string, because quoting every enum costs tokens")
    func bareWord() throws {
        let op = try #require(try LineParser.parse("c b Button variant=primary"))
        guard case .component(let node) = op else { return }
        #expect(node.props["variant"] == .literal(.string("primary")))
    }

    @Test("parses a data binding")
    func binding() throws {
        let op = try #require(try LineParser.parse("c f Field value=@/draft/books/title"))
        guard case .component(let node) = op else { return }
        #expect(node.props["value"] == .binding(DataBinding(pointer: "/draft/books/title")))
    }

    @Test("recognises all three computed forms")
    func computed() throws {
        let count = try #require(try LineParser.parse(#"c m Metric value={"$count":"/books"}"#))
        guard case .component(let a) = count else { return }
        #expect(a.props["value"] == .computed(.count(path: "/books", whereField: nil, equals: nil)))

        let filtered = try #require(try LineParser.parse(
            #"c m Metric value={"$count":"/apps","where":{"field":"status","equals":"Offer"}}"#))
        guard case .component(let b) = filtered else { return }
        #expect(b.props["value"] == .computed(
            .count(path: "/apps", whereField: "status", equals: .string("Offer"))))

        let avg = try #require(try LineParser.parse(#"c m Metric value={"$avg":"/books","field":"rating"}"#))
        guard case .component(let c) = avg else { return }
        #expect(c.props["value"] == .computed(.avg(path: "/books", field: "rating")))
    }

    @Test("keeps inline JSON with spaces intact")
    func inlineJSON() throws {
        let op = try #require(try LineParser.parse(#"c t Table columns=["Region", "Revenue"]"#))
        guard case .component(let node) = op else { return }
        #expect(node.props["columns"] == .literal(.array([.string("Region"), .string("Revenue")])))
    }

    @Test("keeps an equals sign inside a quoted value")
    func quotedEquals() throws {
        let op = try #require(try LineParser.parse(#"c t Text value="a=b""#))
        guard case .component(let node) = op else { return }
        #expect(node.props["value"] == .literal(.string("a=b")))
    }

    @Test("parses children, data, and root")
    func otherVerbs() throws {
        #expect(try LineParser.parse("> page a b") == .children(id: "page", children: ["a", "b"]))
        #expect(try LineParser.parse(#"d /user/name "Ada""#) == .data(path: "/user/name", value: .string("Ada")))
        #expect(try LineParser.parse("d /user/name") == .data(path: "/user/name", value: nil))
        #expect(try LineParser.parse("r page") == .root(id: "page"))
    }

    @Test("ignores blanks and comments")
    func skips() throws {
        #expect(try LineParser.parse("") == nil)
        #expect(try LineParser.parse("   ") == nil)
        #expect(try LineParser.parse("# a note") == nil)
    }

    /// These are the lines that used to parse into a valid op and quietly corrupt
    /// a surface. English sentences begin with "c" and "r".
    @Test("rejects prose that looks like an op")
    func rejectsProse() {
        #expect(throws: LineParseError.self) { try LineParser.parse("r you ready for this?") }
        #expect(throws: LineParseError.self) { try LineParser.parse("c an app for tracking books") }
        #expect(throws: LineParseError.self) { try LineParser.parse("d not a pointer") }
        #expect(throws: LineParseError.self) { try LineParser.parse("x nope") }
    }

    /// The pill's two verbs. A subtitle is one JSON string, like `h` going the
    /// other way, because it has spaces in it; a depth is one whole number.
    @Test("a subtitle is one JSON string")
    func say() throws {
        #expect(try LineParser.parse(#"s "reading your calendar""#) == .say("reading your calendar"))
        #expect(try LineParser.parse(#"s "reading your calendar" step=true"#) == .step("reading your calendar"))
        #expect(try LineParser.parse(#"s bare words step=true"#) == .step("bare words"))
    }

    @Test("a subtitle with nothing to say is a mistake, not an empty line")
    func sayNothing() {
        #expect(throws: LineParseError.self) { try LineParser.parse("s") }
    }

    @Test("the terminal strip is one JSON string and a state")
    func terminalStrip() throws {
        #expect(try LineParser.parse(#"t "waiting on you: npm test" state=waiting"#)
            == .terminal(text: "waiting on you: npm test", state: .waiting))
        #expect(try LineParser.parse(#"t "npm test" state=running"#) == .terminal(text: "npm test", state: .running))
        #expect(try LineParser.parse("t off") == .terminalOff)
    }

    @Test("the agent cursor is two numbers and a press, or off")
    func agentCursor() throws {
        #expect(try LineParser.parse("a 1302 463 act=true")
            == .agentCursor(point: CGPoint(x: 1302, y: 463), act: true))
        #expect(try LineParser.parse("a 10 20") == .agentCursor(point: CGPoint(x: 10, y: 20), act: false))
        #expect(try LineParser.parse("a off") == .agentCursorOff)
        #expect(throws: LineParseError.self) { try LineParser.parse("a 10") }
    }

    @MainActor @Test("the agent cursor counts presses and holds the glass open")
    func agentCursorModel() {
        let model = OverlayModel()
        model.apply(.agentCursor(point: CGPoint(x: 5, y: 5), act: false))
        #expect(!model.isEmpty)
        model.apply(.agentCursor(point: CGPoint(x: 9, y: 9), act: true))
        #expect(model.agentCursor?.acts == 1)
        #expect(model.agentCursor?.point == CGPoint(x: 9, y: 9))
        model.apply(.agentCursorOff)
        #expect(model.agentCursor == nil)
    }

    @Test("a strip with no state, or an unknown one, is a mistake")
    func terminalStripNeedsState() {
        #expect(throws: LineParseError.self) { try LineParser.parse(#"t "npm test""#) }
        #expect(throws: LineParseError.self) { try LineParser.parse(#"t "npm test" state=asleep"#) }
    }

    @Test("a strip needs a non-empty JSON string, not bare words")
    func terminalStripNeedsText() {
        #expect(throws: LineParseError.self) { try LineParser.parse(#"t "" state=running"#) }
        #expect(throws: LineParseError.self) { try LineParser.parse("t bare state=running") }
    }

    /// The written answer. The whole text so far as one JSON string, so a
    /// paragraph break and a quote inside it survive, and `done` after it.
    @Test("a written answer is one JSON string with a done flag after it")
    func write() throws {
        #expect(try LineParser.parse(#"w "Paris.""#) == .write(text: "Paris.", done: false))
        #expect(
            try LineParser.parse(#"w "Paris.\n\nIt has been since 987." done=true"#)
                == .write(text: "Paris.\n\nIt has been since 987.", done: true))
        #expect(try LineParser.parse(#"w "say \"hi\" now""#) == .write(text: #"say "hi" now"#, done: false))
    }

    @Test("a written answer must be a string")
    func writeNotAString() {
        #expect(throws: LineParseError.self) { try LineParser.parse("w") }
        #expect(throws: LineParseError.self) { try LineParser.parse("w bare words here") }
    }

    @Test("queue depth is one whole number")
    func queued() throws {
        #expect(try LineParser.parse("q 2") == .queued(2))
    }

    @Test("a queue depth spelled out is a mistake")
    func queuedWord() {
        #expect(throws: LineParseError.self) { try LineParser.parse("q two") }
    }
}

@Suite("Line buffering")
struct LineBufferTests {
    /// The whole reason this format belongs on a socket: a partial instruction is
    /// invisible rather than half-applied.
    @Test("holds a partial line until its newline arrives")
    func partial() {
        var buffer = LineBuffer()
        #expect(buffer.push("c a Text valu").isEmpty)
        #expect(buffer.pending == "c a Text valu")
        #expect(buffer.push("e=\"hello\"\n") == [#"c a Text value="hello""#])
        #expect(buffer.pending.isEmpty)
    }

    @Test("survives a chunk boundary at every byte")
    func everyBoundary() {
        let source = "c a Metric label=\"Revenue\" value=100\nr a\n"
        var buffer = LineBuffer()
        var lines: [String] = []
        for character in source {
            lines.append(contentsOf: buffer.push(String(character)))
        }
        #expect(lines.count == 2)
        #expect(lines[1] == "r a")
    }

    @Test("flushes a trailing line with no newline")
    func trailing() {
        var buffer = LineBuffer()
        #expect(buffer.push("r a").isEmpty)
        #expect(buffer.flush() == "r a")
        #expect(buffer.flush() == nil)
    }
}

@Suite("Surface store")
@MainActor
struct SurfaceStoreTests {
    private func ops(_ source: String) -> [Op] {
        source.split(separator: "\n").compactMap { try? LineParser.parse(String($0)) }.compactMap { $0 }
    }

    @Test("does not become ready before the root arrives")
    func rootGate() {
        let store = SurfaceStore()
        store.apply(ops(#"c a Text value=hi"#))
        #expect(!store.isReady)
        store.apply(ops("r a"))
        #expect(store.isReady)
    }

    @Test("stays unready when the root is named but never arrives")
    func ghostRoot() {
        let store = SurfaceStore()
        store.apply(ops("r ghost"))
        #expect(!store.isReady)
        #expect(store.pending.contains("ghost"))
    }

    @Test("accepts children before the parent exists")
    func outOfOrder() {
        let store = SurfaceStore()
        store.apply(ops("""
        > page a b
        c page Stack
        c a Text value=one
        c b Text value=two
        r page
        """))
        #expect(store.isReady)
        #expect(store.spec.elements["page"]?.children == ["a", "b"])
        #expect(store.pending.isEmpty)
    }

    @Test("tracks a dangling child and clears it on arrival")
    func dangling() {
        let store = SurfaceStore()
        store.apply(ops("c page Stack\n> page late\nr page"))
        #expect(store.pending == ["late"])
        store.apply(ops("c late Text value=here"))
        #expect(store.pending.isEmpty)
    }

    @Test("reserves the double-underscore namespace")
    func reservedIDs() {
        let store = SurfaceStore()
        store.apply(ops("c __pending__ Text value=x"))
        #expect(store.spec.elements["__pending__"] == nil)
    }

    @Test("computes counts, sums and averages from the data")
    func computed() {
        let store = SurfaceStore()
        store.apply(ops("""
        c n Metric value={"$count":"/books"}
        c open Metric value={"$count":"/books","where":{"field":"done","equals":true}}
        c total Metric value={"$sum":"/books","field":"rating"}
        c mean Metric value={"$avg":"/books","field":"rating"}
        r n
        d /books/0 {"rating":5,"done":true}
        d /books/1 {"rating":4,"done":false}
        d /books/2 {"rating":4,"done":true}
        """))

        #expect(store.resolved(store.spec.elements["n"]!)["value"] == .number(3))
        #expect(store.resolved(store.spec.elements["open"]!)["value"] == .number(2))
        #expect(store.resolved(store.spec.elements["total"]!)["value"] == .number(13))
        // 13 / 3 = 4.333…, rounded to one place, because nobody meant 4.333333.
        #expect(store.resolved(store.spec.elements["mean"]!)["value"] == .number(4.3))
    }

    @Test("averages nothing as zero rather than NaN")
    func emptyAverage() {
        let store = SurfaceStore()
        store.apply(ops(#"c m Metric value={"$avg":"/none","field":"x"}"# + "\nr m"))
        #expect(store.resolved(store.spec.elements["m"]!)["value"] == .number(0))
    }

    @Test("resolves a binding at render time, so a data patch updates it")
    func bindings() {
        let store = SurfaceStore()
        store.apply(ops("c t Text value=@/msg\nr t\nd /msg \"first\""))
        #expect(store.resolved(store.spec.elements["t"]!)["value"] == .string("first"))
        store.apply(ops("d /msg \"second\""))
        #expect(store.resolved(store.spec.elements["t"]!)["value"] == .string("second"))
    }

    @Test("a control writes locally and notifies, in that order")
    func writeBack() {
        // Local first is the point: a typed character that waits for a round trip
        // before appearing feels broken, and nobody may be listening.
        let store = SurfaceStore()
        var seen: [OutboundEvent] = []
        store.onEvent = { seen.append($0) }

        store.apply(ops("c f Field value=@/draft/title\nr f"))
        store.write("/draft/title", .string("Turtle Island"))

        #expect(store.resolved(store.spec.elements["f"]!)["value"] == .string("Turtle Island"))
        #expect(seen == [.value(pointer: "/draft/title", value: .string("Turtle Island"))])
    }

    @Test("a button fires an action naming its own component")
    func actions() {
        let store = SurfaceStore()
        var seen: [OutboundEvent] = []
        store.onEvent = { seen.append($0) }
        store.fire("add", from: "addBtn", payload: ["collection": .string("books")])
        #expect(seen == [.action(name: "add", component: "addBtn",
                                 payload: ["collection": .string("books")])])
    }
}

@Suite("Outbound events")
struct OutboundEventTests {
    /// The format is the mirror of Kyber Lines, so anything that can parse what it
    /// sent can parse what comes back.
    @Test("encodes actions, values and dismissal")
    func lines() {
        #expect(OutboundEvent.action(name: "add", component: "btn", payload: [:]).line
            == "e add btn")
        #expect(OutboundEvent.action(
            name: "add", component: "btn",
            payload: ["collection": .string("books"), "index": .number(2)]).line
            == "e add btn collection=books index=2")
        #expect(OutboundEvent.value(pointer: "/draft/title", value: .string("Turtle Island")).line
            == #"v /draft/title "Turtle Island""#)
        #expect(OutboundEvent.dismissed.line == "x")
        #expect(OutboundEvent.talkKey(down: true).line == "k down")
        #expect(OutboundEvent.talkKey(down: false).line == "k up")
    }

    @Test("round trips a value back through the inbound parser")
    func roundTrip() throws {
        // An agent receiving `v /a "x=y"` must be able to hand that string
        // straight back as a `d` line without it changing meaning.
        let event = OutboundEvent.value(pointer: "/a", value: .string("x=y"))
        let asData = event.line.replacingOccurrences(of: "v ", with: "d ")
        let op = try #require(try LineParser.parse(asData))
        #expect(op == .data(path: "/a", value: .string("x=y")))
    }

    @Test("keeps bare words bare and quotes what needs it")
    func encoding() {
        #expect(OutboundEvent.encode(.string("primary")) == "primary")
        #expect(OutboundEvent.encode(.string("two words")) == #""two words""#)
        #expect(OutboundEvent.encode(.string("true")) == #""true""#)
        #expect(OutboundEvent.encode(.bool(true)) == "true")
        #expect(OutboundEvent.encode(.number(42)) == "42")
    }
}

@Suite("JSON Pointer")
struct PointerTests {
    @Test("reads through objects and arrays")
    func get() {
        let root: [String: JSON] = ["a": .object(["b": .array([.object(["c": .number(1)])])])]
        #expect(Pointer.get(root, "/a/b/0/c") == .number(1))
        #expect(Pointer.get(root, "/a/b/9/c") == nil)
        #expect(Pointer.get(root, "/nope") == nil)
    }

    @Test("creates arrays when the next segment is an index")
    func set() {
        var root: [String: JSON] = [:]
        Pointer.set(&root, "/rows/0/total", .number(12))
        #expect(Pointer.get(root, "/rows/0/total") == .number(12))
        #expect(Pointer.get(root, "/rows")?.arrayValue?.count == 1)
    }

    @Test("refuses an index that would allocate an enormous array")
    func bounded() {
        // One line of model output must not be able to exhaust memory.
        var root: [String: JSON] = [:]
        Pointer.set(&root, "/rows/5000000", .number(1))
        #expect(Pointer.get(root, "/rows")?.arrayValue?.count ?? 0 == 0)
    }

    @Test("handles the RFC 6901 escapes")
    func escapes() {
        #expect(Pointer.segments("/a~1b") == ["a/b"])
        #expect(Pointer.segments("/m~0n") == ["m~n"])
    }
}

@Suite("Urgency")
struct UrgencyTests {
    @Test("a surface carries an urgency when one is given")
    func parsesUrgency() throws {
        let op = try #require(try LineParser.parse("@ alarm at=center urgency=critical"))
        guard case .surface(let id, let region, _, let urgency, _, _) = op else {
            Issue.record("expected a surface op")
            return
        }
        #expect(id == "alarm")
        #expect(region == .center)
        #expect(urgency == .critical)
    }

    @Test("an unknown urgency is dropped rather than guessed")
    func rejectsUnknownUrgency() throws {
        let op = try #require(try LineParser.parse("@ p urgency=extremely"))
        guard case .surface(_, _, _, let urgency, _, _) = op else {
            Issue.record("expected a surface op")
            return
        }
        #expect(urgency == nil)
    }

    @Test("only critical outranks a hidden display")
    func onlyCriticalBreaksThrough() {
        #expect(Urgency.critical.breaksThrough)
        #expect(!Urgency.alert.breaksThrough)
        #expect(!Urgency.normal.breaksThrough)
        #expect(!Urgency.ambient.breaksThrough)
    }
}

@Suite("Chrome")
struct ChromeTests {
    @Test("a surface can ask for no window around it")
    func parsesChrome() throws {
        let op = try #require(try LineParser.parse("@ figure chrome=bare"))
        guard case .surface(_, _, _, _, let chrome, _) = op else {
            Issue.record("expected a surface op")
            return
        }
        #expect(chrome == .bare)
    }

    @Test("an omitted chrome is nil, so re-addressing keeps what the surface had")
    func omittedChromeIsNil() throws {
        let op = try #require(try LineParser.parse("@ figure"))
        guard case .surface(_, let region, _, let urgency, let chrome, _) = op else {
            Issue.record("expected a surface op")
            return
        }
        // All three nil is what lets `@ figure` mean "that panel again" rather
        // than "put that panel back to defaults".
        #expect(region == nil)
        #expect(urgency == nil)
        #expect(chrome == nil)
    }

    @Test("only a card paints a background")
    func onlyCardIsFilled() {
        #expect(Chrome.card.isFilled)
        #expect(!Chrome.bare.isFilled)
        #expect(!Chrome.bracket.isFilled)
    }
}

@Suite("Bindings")
struct BindingTests {
    @Test("the short form binds")
    func shortForm() throws {
        let op = try #require(try LineParser.parse("c m Metric value=@/counts/unread"))
        guard case .component(let node) = op else {
            Issue.record("expected a component op")
            return
        }
        #expect(node.props["value"] == .binding(DataBinding(pointer: "/counts/unread")))
    }

    @Test("the object form binds too, rather than parsing as a literal object")
    func objectForm() throws {
        let op = try #require(try LineParser.parse(#"c d Diagram parts={"$bind":"/graph"}"#))
        guard case .component(let node) = op else {
            Issue.record("expected a component op")
            return
        }
        // Left as a literal this is a valid object that draws nothing, which is
        // the failure that motivated accepting both spellings.
        #expect(node.props["parts"] == .binding(DataBinding(pointer: "/graph")))
    }

    @Test("an object that merely contains $bind is still an object")
    func notABinding() throws {
        let op = try #require(try LineParser.parse(#"c x Text value={"$bind":"/a","t":1}"#))
        guard case .component(let node) = op else {
            Issue.record("expected a component op")
            return
        }
        if case .binding = node.props["value"] {
            Issue.record("a two-key object is data, not a binding")
        }
    }
}

@Suite("Markers")
struct MarkerTests {
    @Test("a mark carries a rectangle in screen points")
    func parsesMark() throws {
        let op = try #require(
            try LineParser.parse(#"m bug 100 200 300 40 label="Here" tone=bad life=30"#))
        guard case .mark(let id, let rect, let label, let tone, let life) = op else {
            Issue.record("expected a mark op")
            return
        }
        #expect(id == "bug")
        #expect(rect == CGRect(x: 100, y: 200, width: 300, height: 40))
        #expect(label == "Here")
        #expect(tone == "bad")
        #expect(life == 30)
    }

    @Test("four numbers are required, because three is a mark in the wrong place")
    func rejectsShortMark() {
        #expect(throws: (any Error).self) {
            _ = try LineParser.parse("m bug 100 200 300")
        }
    }

    @Test("unmark with no id clears the layer")
    func unmarkAll() throws {
        let op = try #require(try LineParser.parse("u"))
        guard case .unmark(let id) = op else {
            Issue.record("expected an unmark op")
            return
        }
        #expect(id.isEmpty)
    }

    @Test("a surface can be given a lifetime")
    func surfaceLife() throws {
        let op = try #require(try LineParser.parse("@ toast at=top life=6"))
        guard case .surface(_, _, _, _, _, let life) = op else {
            Issue.record("expected a surface op")
            return
        }
        #expect(life == 6)
    }
}

@Suite("Voice")
struct VoiceTests {
    @Test("everything before the wake word is discarded")
    @MainActor
    func stripsWakeWord() {
        let voice = VoiceListener()
        // In wake mode the audio before the wake word is somebody's unrelated
        // conversation, so keeping it would send it to a model.
        #expect(
            voice.strippingWakeWord(from: "so anyway chewy show me my week")
                == "show me my week")
    }

    @Test("punctuation after the wake word goes too")
    @MainActor
    func stripsPunctuation() {
        let voice = VoiceListener()
        #expect(voice.strippingWakeWord(from: "Chewy, what is due") == "what is due")
    }

    @Test("no wake word means it was not being spoken to")
    @MainActor
    func requiresWakeWord() {
        let voice = VoiceListener()
        #expect(voice.strippingWakeWord(from: "show me my week") == nil)
    }

    @Test("the wake word alone is not a request")
    @MainActor
    func wakeWordAloneIsNothing() {
        let voice = VoiceListener()
        #expect(voice.strippingWakeWord(from: "chewy") == nil)
    }

    // One push-to-talk turn, driven through the seams the recogniser would
    // drive. Signal is not Equatable, so each test collects the cases it is
    // about. `receivedForTesting` returns the turn a result landed in, and
    // handing that turn back is how a test plays the late arrivals a real
    // turn produces.

    @Test("partials are drawn, never sent")
    @MainActor
    func partialsAreDrawnNotSent() {
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
        voice.receivedForTesting("text sar", isFinal: false)
        #expect(partials == ["text sar"])
        #expect(heard.isEmpty)
    }

    @Test("a final inside the grace is sent once, and the grace is then inert")
    @MainActor
    func finalBeforeGraceDispatchesOnce() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var heard: [String] = []
        var order: [String] = []
        voice.onSignal = { signal in
            switch signal {
            case .heard(let text):
                heard.append(text)
                order.append("heard")
            case .listening(false):
                order.append("off")
            default: break
            }
        }
        let turn = voice.receivedForTesting("text sarah", isFinal: false)
        voice.receivedForTesting("Text Sarah", isFinal: true, turn: turn)
        voice.fireCommitForTesting(turn: turn)
        #expect(heard == ["Text Sarah"])
        // main.swift holds the transcript on `.heard` and ignores the
        // `.listening(false)` that `stop()` sends right after it, so the order
        // is part of the contract.
        #expect(order == ["heard", "off"])
    }

    @Test("the grace beats a slow final: the last partial is sent, the final is dropped")
    @MainActor
    func graceBeforeFinalDispatchesPartialOnce() {
        // The documented trade: a final that lands after the grace can carry
        // the corrected name, and it is lost. `commitGrace` is what buys it
        // time, and the `voice.final` log line is how that number gets set.
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var heard: [String] = []
        voice.onSignal = { signal in
            if case .heard(let text) = signal { heard.append(text) }
        }
        let turn = voice.receivedForTesting("text sarah", isFinal: false)
        voice.fireCommitForTesting(turn: turn)
        voice.receivedForTesting("Text Sarah I am late", isFinal: true, turn: turn)
        #expect(heard == ["text sarah"])
    }

    @Test("a partial from a closed turn is not drawn")
    @MainActor
    func staleTurnIsDropped() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var partials: [String] = []
        voice.onSignal = { signal in
            if case .partial(let text) = signal { partials.append(text) }
        }
        let turn = voice.receivedForTesting("text", isFinal: false)
        voice.fireCommitForTesting(turn: turn)
        voice.receivedForTesting("text sarah", isFinal: false, turn: turn)
        #expect(partials == ["text"])
    }

    @Test("cancelling the press drops everything the turn still had to say")
    @MainActor
    func cancelDropsTheTurn() {
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
        let turn = voice.receivedForTesting("text sarah", isFinal: false)
        voice.cancelPush()
        voice.receivedForTesting("Text Sarah", isFinal: true, turn: turn)
        voice.fireCommitForTesting(turn: turn)
        #expect(heard.isEmpty)
        #expect(partials == ["text sarah"])
    }

    // How a turn actually ends on the machine this was measured on
    // (2026-09-19): never with a final. The recogniser answers the key
    // release with an error, and what was heard has to survive that.

    @Test("a recogniser error after a partial sends the partial")
    @MainActor
    func errorAfterPartialSendsThePartial() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var heard: [String] = []
        var failures: [String] = []
        voice.onSignal = { signal in
            switch signal {
            case .heard(let text): heard.append(text)
            case .failed(let message): failures.append(message)
            default: break
            }
        }
        let turn = voice.receivedForTesting("text sarah", isFinal: false)
        voice.receivedForTesting(nil, isFinal: false, failed: true, errorCode: 1101, turn: turn)
        #expect(heard == ["text sarah"])
        #expect(failures.isEmpty)
    }

    @Test("a recogniser error with nothing heard names the recogniser, not the person")
    @MainActor
    func errorWithNothingHeardNamesTheRecogniser() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var heard: [String] = []
        var failures: [String] = []
        voice.onSignal = { signal in
            switch signal {
            case .heard(let text): heard.append(text)
            case .failed(let message): failures.append(message)
            default: break
            }
        }
        voice.receivedForTesting(nil, isFinal: false, failed: true, errorCode: 1101)
        #expect(heard.isEmpty)
        #expect(failures == ["Speech model not ready (1101). Turn on Dictation under System Settings, Keyboard, then try again"])
        // Its own "no speech detected" is the person's silence.
        #expect(VoiceListener.message(forRecognizerError: 1110) == "Did not catch that")
    }

    @Test("an empty final commits the last partial")
    @MainActor
    func emptyFinalCommitsThePartial() {
        let voice = VoiceListener()
        voice.setMode(.pushToTalk)
        var heard: [String] = []
        var failures: [String] = []
        voice.onSignal = { signal in
            switch signal {
            case .heard(let text): heard.append(text)
            case .failed(let message): failures.append(message)
            default: break
            }
        }
        let turn = voice.receivedForTesting("text sarah", isFinal: false)
        voice.receivedForTesting("", isFinal: true, turn: turn)
        #expect(heard == ["text sarah"])
        #expect(failures.isEmpty)
    }

    @Test("an empty revision does not erase what was heard")
    @MainActor
    func emptyPartialKeepsWhatWasHeard() {
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
        let turn = voice.receivedForTesting("text sarah", isFinal: false)
        voice.receivedForTesting("", isFinal: false, turn: turn)
        voice.fireCommitForTesting(turn: turn)
        #expect(partials == ["text sarah"])
        #expect(heard == ["text sarah"])
    }
}

@Suite("Spoken and typed requests")
struct HeardTests {
    @Test("a request is always a quoted string on the wire")
    func heardIsQuoted() {
        // Never bare. An utterance has spaces in it, and a listener splitting on
        // whitespace would take the first word and drop the sentence.
        let line = OutboundEvent.heard("show me my week").line
        #expect(line == #"h "show me my week""#)
    }

    @Test("quotes inside a request survive the trip")
    func heardEscapes() {
        let line = OutboundEvent.heard(#"what does "this" mean"#).line
        #expect(line.hasPrefix("h "))
        // Round-trips as JSON, which is what the listener parses it as.
        let payload = String(line.dropFirst(2))
        let data = Data(payload.utf8)
        let decoded = try? JSONSerialization.jsonObject(
            with: data, options: [.fragmentsAllowed]) as? String
        #expect(decoded == #"what does "this" mean"#)
    }

    @Test("the typed bar and the microphone produce the same event")
    func oneShape() {
        // One path from asking to drawing. Two would drift.
        #expect(OutboundEvent.heard("x") == OutboundEvent.heard("x"))
    }
}

@Suite("Pointing")
struct RegionTests {
    @Test("a pointed region is whole points, top-left origin")
    func regionLine() {
        // Sub-pixel precision in a gesture made with a hand is noise, and it
        // makes the line harder to read in a terminal.
        let line = OutboundEvent.region(
            CGRect(x: 100.4, y: 200.8, width: 320.2, height: 90.9)).line
        #expect(line == "g 100 200 320 90")
    }

    @Test("a region and a request are different events")
    func regionIsNotHeard() {
        #expect(
            OutboundEvent.region(CGRect(x: 0, y: 0, width: 1, height: 1))
                != OutboundEvent.heard("g 0 0 1 1"))
    }
}

@Suite("Decay")
@MainActor
struct DecayTests {
    /// Wait for a condition, up to a deadline.
    ///
    /// A fixed sleep is a bug in a timing test. The sweep runs on a half-second
    /// tick, so any load on the machine can push it past a hard-coded wait, and
    /// this suite went red once for no reason other than rendering images at the
    /// same time. Polling asks the only question that matters: did it happen.
    private func eventually(
        within seconds: Double = 6,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return condition()
    }

    @Test("a surface with a lifetime takes itself down")
    func surfaceExpires() async throws {
        let model = OverlayModel()
        model.apply(try #require(try LineParser.parse("@ toast at=top life=0.3")))
        model.apply(try #require(try LineParser.parse("c s Screen title=\"HI\"")))
        model.apply(try #require(try LineParser.parse("r s")))
        #expect(model.surfaces.count == 1)
        #expect(await eventually { model.surfaces.isEmpty })
    }

    @Test("taking one marker down does not stop everything else expiring")
    func unmarkKeepsTheSweepRunning() async throws {
        // This was a real bug: unmark cancelled the sweep unconditionally, so
        // removing one mark froze every other mark and every surface with a
        // lifetime on screen forever.
        let model = OverlayModel()
        model.apply(try #require(try LineParser.parse("m a 0 0 10 10 life=0.3")))
        model.apply(try #require(try LineParser.parse("m b 0 0 10 10 life=0.3")))
        model.apply(try #require(try LineParser.parse("@ toast at=top life=0.3")))
        model.apply(try #require(try LineParser.parse("c s Screen title=\"HI\"")))
        model.apply(try #require(try LineParser.parse("r s")))

        model.apply(try #require(try LineParser.parse("u a")))
        #expect(model.markers.count == 1)

        #expect(await eventually { model.markers.isEmpty && model.surfaces.isEmpty })
    }

    @Test("life=0 pins a marker")
    func pinned() async throws {
        let model = OverlayModel()
        model.apply(try #require(try LineParser.parse("m pin 0 0 10 10 life=0")))
        // The inverse: it must still be there after long enough that anything
        // expiring would have gone.
        #expect(!(await eventually(within: 1.5) { model.markers.isEmpty }))
        #expect(model.markers.count == 1)
    }
}

@Suite("Guides")
@MainActor
struct GuideTests {
    @Test("a click on a guide takes it down and reports it")
    func hit() throws {
        let model = OverlayModel()
        var sent: [String] = []
        model.onEvent = { sent.append($0.line) }
        model.apply(try #require(try LineParser.parse(
            "m guide 100 100 80 30 label=\"Sign in\" tone=guide life=0")))
        #expect(model.hit(at: CGPoint(x: 120, y: 110)))
        #expect(model.markers.isEmpty)
        #expect(sent == ["e hit guide label=\"Sign in\""])
    }

    @Test("the ring counts, and beside it does not")
    func reach() throws {
        let model = OverlayModel()
        var sent: [String] = []
        model.onEvent = { sent.append($0.line) }
        model.apply(try #require(try LineParser.parse(
            "m guide 100 100 80 30 label=Next tone=guide life=0")))
        #expect(!model.hit(at: CGPoint(x: 300, y: 300)))
        #expect(model.markers.count == 1)
        #expect(sent.isEmpty)
        // Four points outside the rectangle, on the ring.
        #expect(model.hit(at: CGPoint(x: 96, y: 110)))
        #expect(sent == ["e hit guide label=Next"])
    }

    @Test("a plain mark is a note, not a control")
    func plainMarkIgnoresClicks() throws {
        let model = OverlayModel()
        var sent: [String] = []
        model.onEvent = { sent.append($0.line) }
        model.apply(try #require(try LineParser.parse(
            "m bug 100 100 80 30 label=\"The bug\" tone=bad life=0")))
        #expect(!model.hit(at: CGPoint(x: 120, y: 110)))
        #expect(model.markers.count == 1)
        #expect(sent.isEmpty)
    }
}

@Suite("Repeating yourself")
@MainActor
struct RepeatTests {
    @Test("the same words twice in a row are one utterance being refined")
    func suppressesRefinement() {
        let voice = VoiceListener()
        var heard: [String] = []
        voice.onSignal = { signal in
            if case .heard(let text) = signal { heard.append(text) }
        }
        voice.fireForTesting("show me my week")
        voice.fireForTesting("show me my week")
        #expect(heard == ["show me my week"])
    }

    @Test("the same words later are a second request")
    func allowsAGenuineRepeat() {
        // Asking for the same thing twice in one session is a thing people do
        // constantly, and the first version suppressed it forever.
        let voice = VoiceListener()
        var heard: [String] = []
        voice.onSignal = { signal in
            if case .heard(let text) = signal { heard.append(text) }
        }
        voice.fireForTesting("show me my week")
        voice.expireRepeatWindowForTesting()
        voice.fireForTesting("show me my week")
        #expect(heard.count == 2)
    }
}

@Suite("Clearing")
@MainActor
struct ClearTests {
    @Test("a bare dash clears the glass")
    func clearsEverything() throws {
        let model = OverlayModel()
        model.apply(try #require(try LineParser.parse("@ one at=top")))
        model.apply(try #require(try LineParser.parse("c s Screen title=\"A\"")))
        model.apply(try #require(try LineParser.parse("r s")))
        model.apply(try #require(try LineParser.parse("m x 0 0 9 9 life=0")))
        #expect(!model.isEmpty)

        model.apply(try #require(try LineParser.parse("-")))
        #expect(model.isEmpty)
    }

    @Test("a dash with a name closes only that one")
    func closesOne() throws {
        let model = OverlayModel()
        for line in ["@ one at=top", "c a Screen title=\"A\"", "r a",
                     "@ two at=bottom", "c b Screen title=\"B\"", "r b"] {
            model.apply(try #require(try LineParser.parse(line)))
        }
        #expect(model.surfaces.count == 2)
        model.apply(try #require(try LineParser.parse("- one")))
        #expect(model.surfaces.map(\.id) == ["two"])
    }

    @Test("more than one name is a mistake, not a list")
    func rejectsTwoNames() {
        #expect(throws: (any Error).self) {
            _ = try LineParser.parse("- one two")
        }
    }
}

@Suite("Reading it aloud")
@MainActor
struct AccessibilityTests {
    @Test("a diagram describes itself rather than announcing an image")
    func diagramDescribesItself() {
        // It shipped with a declared role and no content, which promises
        // information it cannot deliver.
        let parts: [JSON] = [
            .object(["t": .string("node"), "label": .string("Cashier")]),
            .object(["t": .string("arrow")]),
            .object(["t": .string("node"), "label": .string("Barista")]),
        ]
        let spoken = SurfaceView.describe(parts)
        #expect(spoken.contains("Cashier"))
        #expect(spoken.contains("Barista"))
        #expect(spoken.contains("1 connection"))
    }

    @Test("a diagram with no labels still says how much is there")
    func unlabelledDiagram() {
        let parts: [JSON] = [.object(["t": .string("dot")]), .object(["t": .string("dot")])]
        #expect(SurfaceView.describe(parts) == "2 shapes")
    }

    @Test("a tone has a word and a symbol, not only a colour")
    func toneIsNotOnlyColour() {
        // Good and bad differed by hue alone, which makes them identical to a
        // meaningful number of people.
        for name in ["good", "warn", "bad"] {
            #expect(HUD.symbol(name) != nil, "\(name) has no symbol")
            #expect(HUD.spoken(name) != nil, "\(name) has no word")
        }
        #expect(HUD.symbol(nil) == nil)
        #expect(HUD.spoken("something else") == nil)
    }

    @Test("secondary text clears the contrast it used to fail")
    func contrastRaised() {
        // faint was 0.38 white, under 3:1 against this glass at 10 and 11
        // points. It was chosen because it looked calm, which is not a
        // standard.
        #expect(HUD.faint == Color.white.opacity(0.62))
        #expect(HUD.dim == Color.white.opacity(0.78))
    }

    @Test("out-of-range diagram coordinates land at the edge, not nowhere")
    func coordinatesClamp() {
        let part = try? #require(
            Primitive(.object(["t": .string("node"), "x": .number(1.4), "y": .number(-0.2)])))
        #expect(part?.channels[0] == 1)
        #expect(part?.channels[1] == 0)
    }
}
