import Testing
@testable import BobHUDKit

/// The Swift parser and store are ports of the TypeScript, so they need the same
/// guarantees tested the same way. A port that drifts is worse than no port: the
/// panel would render something subtly different from every other surface.

@Suite("Bob Lines")
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
    /// The format is the mirror of Bob Lines, so anything that can parse what it
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
        guard case .surface(let id, let region, _, let urgency, _) = op else {
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
        guard case .surface(_, _, _, let urgency, _) = op else {
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
        guard case .surface(_, _, _, _, let chrome) = op else {
            Issue.record("expected a surface op")
            return
        }
        #expect(chrome == .bare)
    }

    @Test("an omitted chrome is nil, so re-addressing keeps what the surface had")
    func omittedChromeIsNil() throws {
        let op = try #require(try LineParser.parse("@ figure"))
        guard case .surface(_, let region, _, let urgency, let chrome) = op else {
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
