import Foundation

/// The words people say as punctuation, for dictation.
public enum Spoken {
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
    /// half of this job is Whisper's, which reads the whole sentence and can
    /// tell the two apart.
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
}
