import CoreGraphics
import Foundation

/// What the panel sends back up the socket.
///
/// The format is the mirror image of Bob Lines and deliberately just as small.
/// An agent that can parse what it sent can parse what comes back, and a person
/// debugging this can read it in a terminal.
///
///     e <action> <componentId> [key=value ...]     a control was used
///     v <pointer> <json>                           a bound value changed
///     x                                            the panel was dismissed
///     h <json string>                              something was said to it
///     g <x> <y> <w> <h>                            a region was pointed at
///     ! <json string>                              something you sent was wrong
///     v! <json string>                             the display's version
///
/// Values echo the same encoding as inbound props, so `label="Send it"` means
/// the same thing in both directions.
public enum OutboundEvent: Sendable, Equatable {
    case action(name: String, component: ComponentID, payload: [String: JSON])
    case value(pointer: String, value: JSON)
    case dismissed
    /// A spoken request, wake word already removed. Always a quoted JSON string,
    /// never bare: an utterance has spaces in it and a listener splitting on
    /// whitespace would otherwise take the first word and drop the sentence.
    case heard(String)
    /// A region of the screen the person pointed at, in points with a top-left
    /// origin. Deixis: this is what makes "what is this" mean something.
    case region(CGRect)
    /// Something the sender got wrong.
    ///
    /// Nothing used to go back. A misspelled component, a dropped prop, a line
    /// that failed to parse: all of it was swallowed, and the sender saw
    /// success. That is the failure mode that makes every other bug here hard
    /// to find, because the first thing you learn is that silence means
    /// nothing at all.
    case problem(String)
    /// What this build is, so a client can tell before it relies on something.
    case version(String)

    public var line: String {
        switch self {
        case .action(let name, let component, let payload):
            let props = payload
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(OutboundEvent.encode($0.value))" }
                .joined(separator: " ")
            return "e \(name) \(component)\(props.isEmpty ? "" : " " + props)"

        case .value(let pointer, let value):
            return "v \(pointer) \(OutboundEvent.encode(value))"

        case .dismissed:
            return "x"

        case .heard(let text):
            return "h \(OutboundEvent.jsonString(text))"

        case .problem(let text):
            return "! \(OutboundEvent.jsonString(text))"

        case .version(let text):
            return "v! \(OutboundEvent.jsonString(text))"

        case .region(let rect):
            // Whole points. Sub-pixel precision in a gesture made with a hand
            // is noise, and it makes the line harder to read in a terminal.
            return "g \(Int(rect.minX)) \(Int(rect.minY)) "
                + "\(Int(rect.width)) \(Int(rect.height))"
        }
    }

    /// Bare words stay bare, because quoting every enum value costs bytes and
    /// reads worse, and the inbound parser already accepts both.
    static func encode(_ value: JSON) -> String {
        switch value {
        case .string(let s):
            let bare = !s.isEmpty
                && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
                && !["true", "false", "null"].contains(s)
            return bare ? s : jsonString(s)
        case .number(let n):
            return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array, .object:
            guard let data = try? JSONSerialization.data(withJSONObject: value.foundationValue),
                  let text = String(data: data, encoding: .utf8)
            else { return "null" }
            return text
        }
    }

    static func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: s, options: [.fragmentsAllowed]),
              let text = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return text
    }
}

extension JSON {
    /// Back to Foundation types, for serialising arrays and objects.
    var foundationValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .null: return NSNull()
        case .array(let a): return a.map(\.foundationValue)
        case .object(let o): return o.mapValues(\.foundationValue)
        }
    }
}
