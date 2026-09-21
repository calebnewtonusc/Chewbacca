import Foundation

/// A dictation bubble: a small circle the person drags onto a text box.
///
/// ## Why this exists
///
/// The display already listens. Holding the talk key sends what you said to the
/// assistant, which reads it, decides what you meant and acts. That is the right
/// behaviour for a request and the wrong behaviour for a sentence you want typed
/// somewhere, and the failure is not hypothetical: asked on 2026-09-21 to
/// "create a bubble" with Terminal in front, the router classified it as
/// terminal work and came back offering to draft a prompt. Anything spoken at an
/// assistant is a candidate for interpretation, and the only way out of that is
/// a destination the person named themselves rather than one a model guessed.
///
/// The bubble is that destination. It carries no intelligence at all. It is a
/// pin in a text box saying "the words go here", and the whole feature is the
/// difference between speaking to be understood and speaking to be transcribed.
///
/// ## The lifecycle, as states
///
/// One bubble moves through these in order, and every one of them is a different
/// thing on the glass, because a bubble that looks the same when it is bound and
/// when it is not is a bubble that loses somebody's sentence.
///
/// - `unbound`: just spawned beside the pill, sitting on nothing. Drag it.
/// - `idle`: bound to a field, its window in front. Click to talk.
/// - `dimmed`: bound, but its application is not frontmost. Still bound, drawn
///   faint, and a click brings the field forward rather than starting a turn:
///   dictating into a window you cannot see is how text lands in the wrong app.
/// - `live`: the microphone is open and the words are appearing in the bubble.
/// - `thinking`: the turn closed and the text is being cleaned and inserted.
/// - `orphaned`: the field is gone. The bubble stays put and says so rather than
///   rebinding to whatever is now underneath.
public enum BubbleState: String, Sendable, Equatable {
    case unbound, idle, dimmed, live, thinking, orphaned
}

/// One bubble on the glass.
///
/// Position is the centre, in screen points with a top-left origin, which is
/// what the accessibility API and every screenshot use. The display converts
/// AppKit's bottom-left mouse location exactly once, in `flipped`.
public struct Bubble: Identifiable, Sendable, Equatable {
    public let id: String
    public var center: CGPoint
    public var state: BubbleState
    /// What is being heard right now, drawn beside the bubble while `live`.
    /// Never acted on: this is the recogniser still revising itself.
    public var heard: String
    /// The application the bound field belongs to, for the label.
    public var app: String?
    /// Why it is not usable, when it is not: "no text field there",
    /// "accessibility not granted", "the field is gone".
    public var note: String?

    public init(
        id: String, center: CGPoint, state: BubbleState = .unbound,
        heard: String = "", app: String? = nil, note: String? = nil
    ) {
        self.id = id
        self.center = center
        self.state = state
        self.heard = heard
        self.app = app
        self.note = note
    }

    /// The circle's diameter.
    ///
    /// 34 points. Fitts's law wants a 44 point target and this is smaller on
    /// purpose, because the thing it sits on top of is a text field 22 points
    /// tall in most applications and a 44 point circle covers the field it is
    /// pointing at. The interactive rectangle is padded to 44 in
    /// `hitFrame` instead, so the tap target meets the floor while the drawn
    /// circle stays out of the way.
    public static let size: CGFloat = 34

    /// The gap between the drawn circle and the edge of what answers a click.
    /// Five points each side takes a 34 point circle to a 44 point target.
    public static let touchSlop: CGFloat = 5

    /// How often a bound bubble asks where its field has moved to.
    ///
    /// 10Hz. A window drag at 60fps moves under the bubble for up to 100ms
    /// before it catches up, which reads as the bubble being attached by a short
    /// elastic rather than as a bug, and it costs one accessibility round trip
    /// per tick against a budget where the same call measured under 2ms. Faster
    /// was tried at 30Hz and the only difference on this machine was three times
    /// the IPC; guessed above that, never measured past 30.
    public static let poll: TimeInterval = 0.1

    /// How far the pointer may travel between press and release for it to still
    /// count as a click rather than a drag.
    ///
    /// 4 points. A deliberate drag crosses this in the first frame. The reason
    /// it is not zero is that pressing a physical trackpad moves the cursor one
    /// or two points, so a threshold of zero turned roughly one click in four
    /// into a one-pixel drag that rebound the bubble to the same field and did
    /// not start the turn, which felt like the bubble ignoring the click.
    public static let clickSlop: CGFloat = 4

    /// The rectangle drawn on the glass.
    public var frame: CGRect {
        CGRect(
            x: center.x - Self.size / 2, y: center.y - Self.size / 2,
            width: Self.size, height: Self.size)
    }

    /// The rectangle that answers a click: the circle, padded to a 44 point
    /// target.
    public var hitFrame: CGRect {
        frame.insetBy(dx: -Self.touchSlop, dy: -Self.touchSlop)
    }

    /// Bound to a field, whether or not that field's window is in front.
    public var isBound: Bool {
        state == .idle || state == .dimmed || state == .live || state == .thinking
    }

    /// Turn a spoken sentence into something worth typing.
    ///
    /// Deterministic and conservative. The recogniser already capitalises and
    /// punctuates a sentence it is confident about; what it does not do is
    /// honour the words people say *as* punctuation, which is most of what
    /// anybody means by dictation.
    ///
    /// **Where it stops, and why.** A single word like "period" or "comma" is
    /// substituted only as the last word of the utterance. "A period of time",
    /// "the colon", "a semicolon in the query" are all real sentences, and a
    /// rule that fired mid-utterance would turn one of them into "a. of time".
    /// Destroying a sentence is worse than missing a comma, so the aggressive
    /// half of this job is the clean-up hop's, which reads the whole sentence
    /// and can tell the two apart. That is the hop's reason to exist: without
    /// this line it is an optional nicety, and with it the division is real.
    ///
    /// The multi-word forms are substituted anywhere, because "question mark"
    /// and "new paragraph" do not occur in dictated prose by accident.
    public static func punctuate(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Longest first, so "exclamation mark" is not read as "mark".
        let phrases: [(String, String)] = [
            ("question mark", "?"), ("exclamation mark", "!"),
            ("exclamation point", "!"), ("new paragraph", "\n\n"),
            ("new line", "\n"),
        ]
        for (word, glyph) in phrases {
            // Whitespace on both sides is eaten, because the break itself is
            // the whitespace: leaving the trailing space put "dear sam\n\n
            // thanks" in somebody's mail, indented by one space.
            let both = glyph.hasPrefix("\n")
            text = text.replacingOccurrences(
                of: "\\s*\\b\(word)\\b" + (both ? "\\s*" : ""), with: glyph,
                options: [.regularExpression, .caseInsensitive])
        }

        let finals: [(String, String)] = [
            ("full stop", "."), ("period", "."), ("comma", ","),
            ("semicolon", ";"), ("colon", ":"),
        ]
        for (word, glyph) in finals {
            text = text.replacingOccurrences(
                of: "\\s*\\b\(word)\\b\\s*[.!?]?$", with: glyph,
                options: [.regularExpression, .caseInsensitive])
        }

        // The substitutions leave "there?Then" when a sentence continues, so a
        // space goes back after any mark that is not at the end.
        text = text.replacingOccurrences(
            of: "([.,;:?!])(?=[A-Za-z0-9])", with: "$1 ",
            options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// One line of what the bubble is for, spoken and drawn.
    public var label: String {
        switch state {
        case .unbound: return "drag me onto a text box"
        case .idle: return app.map { "dictate into \($0)" } ?? "click to dictate"
        case .dimmed: return app.map { "bring \($0) forward" } ?? "not in front"
        case .live: return heard.isEmpty ? "listening" : heard
        case .thinking: return "writing it in"
        case .orphaned: return note ?? "the field is gone"
        }
    }
}
