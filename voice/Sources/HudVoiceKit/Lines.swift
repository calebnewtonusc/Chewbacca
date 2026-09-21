import Foundation

/// The protocol hud-speak spoke, kept to the letter so the bridge cannot
/// tell which voice server is behind the pipe.
///
/// In, one JSON object per line: `{"say": text, "more": bool}` cuts off
/// what was playing and starts this; `{"add": text}` queues behind it;
/// `{"end": true}` closes the reply so quiet can follow its last sentence;
/// `{"hush": true}` stops everything. Out: `{"level": 0..1}` twenty times a
/// second while sound plays, `{"saying": sentence}` before each sentence
/// starts, `{"quiet": true}` when nothing more is coming, and
/// `{"status": text}` for the pill while the voice is not ready yet. The
/// word `ready` alone means the model is loaded and warm.
public enum Lines {
    public enum Message: Equatable, Sendable {
        case say(String, more: Bool)
        case add(String)
        case end
        case hush
    }

    public static func parse(_ line: String) -> Message? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let hush = object["hush"] as? Bool, hush { return .hush }
        if let end = object["end"] as? Bool, end { return .end }
        if let text = (object["say"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return .say(text, more: (object["more"] as? Bool) ?? false)
        }
        if let text = (object["add"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return .add(text)
        }
        return nil
    }

    public static func level(_ value: Float) -> String {
        let clamped = min(max(value, 0), 1)
        return "{\"level\": \((clamped * 100).rounded() / 100)}"
    }

    public static func saying(_ text: String) -> String {
        encode(["saying": text])
    }

    public static func status(_ text: String) -> String {
        encode(["status": text])
    }

    public static let quiet = "{\"quiet\": true}"

    private static func encode(_ object: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    /// Sentence ends, as hud-speak split them: after `.`, `!` or `?` and a
    /// space, so the first sentence starts playing while the second is
    /// still being made. A fragment under three words joins the sentence
    /// before it rather than paying for its own generation and pause.
    public static func sentences(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var parts: [String] = []
        var current = ""
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            current.append(character)
            let next = trimmed.index(after: index)
            if ".!?".contains(character), next < trimmed.endIndex, trimmed[next].isWhitespace {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            index = next
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            parts.append(current.trimmingCharacters(in: .whitespaces))
        }
        var out: [String] = []
        for part in parts where !part.isEmpty {
            if !out.isEmpty, part.split(separator: " ").count < 3 {
                out[out.count - 1] += " " + part
            } else {
                out.append(part)
            }
        }
        // A short opening ("Dr." before the name, "Yes." before the reason)
        // is not worth its own generation and pause either: it goes with
        // the sentence after it.
        if out.count > 1, out[0].split(separator: " ").count < 3 {
            out[1] = out[0] + " " + out[1]
            out.removeFirst()
        }
        return out
    }
}

/// How loud each frame of a clip is, 0 to 1, for the ring.
///
/// RMS per frame against the loudest frame of the same clip, so every
/// sentence uses the whole range of the ring however softly it was said,
/// then raised to 0.7 so the dips between words stay visible instead of
/// flattening into the vowels. The same curve hud-speak drew; guessed
/// against the eye, never measured.
public enum Envelope {
    /// The frame the ring animates its stroke over (PresenceRing: 0.06s
    /// linear); a coarser envelope would step and a finer one is thrown
    /// away.
    public static let frame = 0.05

    public static func of(_ samples: [Float], sampleRate: Int, frame: Double = frame) -> [Float] {
        let width = max(1, Int(Double(sampleRate) * frame))
        let frames = samples.count / width
        guard frames > 0 else { return [] }
        var levels = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            var sum: Float = 0
            for sample in samples[(i * width)..<((i + 1) * width)] { sum += sample * sample }
            levels[i] = (sum / Float(width)).squareRoot()
        }
        let peak = levels.max() ?? 0
        guard peak > 1e-4 else { return [Float](repeating: 0, count: frames) }
        return levels.map { Float(pow(Double(min(max($0 / peak, 0), 1)), 0.7)) }
    }
}
