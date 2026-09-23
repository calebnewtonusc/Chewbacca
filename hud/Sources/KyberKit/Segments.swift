import Foundation

/// One held press can be several recogniser segments, and only the listener
/// can stitch them back into what was said.
///
/// Apple's on-device recogniser starts its transcript over after a pause:
/// "I need to finish the essay tonight." is followed by a partial that reads
/// "and", not by one that reads "...tonight. And". The final does the same.
/// Taking each result as the whole utterance kept only what came after the
/// last pause. On 2026-09-22 a twelve-second dictation into Terminal
/// committed 24 characters (`voice.turn source=final partial_chars=24`)
/// while Whisper, reading the same audio, heard 93, and live the typer had
/// deleted the first sentence to show the second.
public enum Segments {
    /// Whether `next` starts a new segment rather than revising `current`.
    ///
    /// `closed` is the recogniser's own word for it: the previous result
    /// carried `speechRecognitionMetadata`, which it attaches to the result
    /// that ends a segment. The length rule is the backstop for a restart
    /// that arrives without it, and is shaped so that an ordinary revision
    /// can never pass it: a revision keeps about the same number of words,
    /// and a restart begins at one or two.
    public static func isRestart(current: String, next: String, closed: Bool) -> Bool {
        let old = normalized(current)
        let new = normalized(next)
        guard !old.isEmpty, !new.isEmpty else { return false }
        let shorter = new.count * 2 <= old.count
        // After the recogniser's own boundary, a new first word is a new
        // segment, and so is the same first word at half the length: "I will"
        // after "I need to finish the essay tonight." A revision after the
        // boundary keeps both ("text sara" to "Text Sarah").
        if closed { return old[0] != new[0] || shorter }
        // Without it, agreeing on the opening words is a revision or a
        // continuation, whatever else happened, because stitching it on would
        // say the sentence twice.
        let opening = min(2, old.count, new.count)
        if Array(old.prefix(opening)) == Array(new.prefix(opening)) { return false }
        return old.count >= 3 && shorter
    }

    /// `settled` and `current` as one transcript. A `current` that already
    /// begins with everything settled (a recogniser that did not restart
    /// after all, or a final that repeats the whole turn) is taken as it is,
    /// so nothing is said twice.
    public static func join(_ settled: String, _ current: String) -> String {
        let head = settled.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return tail }
        if tail.isEmpty { return head }
        let settledWords = normalized(head)
        if normalized(tail).starts(with: settledWords) { return tail }
        return head + " " + tail
    }

    /// Lowercased words with their punctuation off, because the recogniser
    /// capitalises and punctuates a segment once it is finished, and
    /// "tonight." ending one result is "tonight" in the one before.
    static func normalized(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
    }
}
