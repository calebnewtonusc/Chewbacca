import Foundation

/// The words the recogniser is told to expect: the names of the people the
/// person talks to, and the names this assistant answers to.
///
/// Apple's on-device recogniser spells a name it has never seen as the
/// nearest common word, and a name heard wrong is a text sent to the wrong
/// person. `contextualStrings` is the API for exactly this, a list of
/// phrases weighted up during recognition. The bridge writes the names it
/// finds in Messages and Contacts to `names.txt` when it starts;
/// `vocabulary.txt` beside it is the person's own list, one word or phrase
/// per line, and nothing writes it but them.
public enum Vocabulary {
    public static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".bob")
    public static let files = ["vocabulary.txt", "names.txt"]
    /// Beyond this the list is cut. Apple documents no limit, and a list of
    /// every contact on a Mac with two thousand of them is a list the
    /// recogniser weighs on every partial. 300: guessed, never measured.
    public static let cap = 300
    /// What the assistant is called, so "text Chewie" is not "text chewy".
    public static let own = ["Chewbacca", "Chewie", "Chewy"]

    public static func load() -> [String] {
        var text = ""
        for name in files {
            let url = directory.appendingPathComponent(name)
            if let more = try? String(contentsOf: url, encoding: .utf8) {
                text += more + "\n"
            }
        }
        return words(from: text, cap: cap)
    }

    /// The phrases in `text`, one per line, with the assistant's own names
    /// first, then the first word of every line (a first name is what gets
    /// said), then the lines in full, deduplicated without regard to case
    /// and cut at `cap`. A line starting with # is a comment.
    public static func words(from text: String, cap: Int = cap) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        func add(_ phrase: Substring) {
            let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 1, !trimmed.hasPrefix("#"), out.count < cap else { return }
            guard seen.insert(trimmed.lowercased()).inserted else { return }
            out.append(trimmed)
        }
        for name in own { add(Substring(name)) }
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        for line in lines {
            if let first = line.split(separator: " ").first { add(first) }
        }
        for line in lines { add(Substring(line)) }
        return out
    }
}
