import Foundation

/// Bob Lines, ported from `src/core/lines.ts`.
///
/// The format is four verbs, one instruction per line:
///
///     c <id> <Type> [prop=value ...]     declare a component
///     > <id> <child> [child ...]         give it children
///     d <pointer> <json>                 patch the data model
///     r <id>                             declare the root
///     @ <surface> [at=region] [w=380] [urgency=alert] [chrome=bare] [life=60]
///                                        open or switch to a surface
///     - <surface>
///     p <state> [amp=0.4]                presence: what it is doing
///     m <id> <x> <y> <w> <h> [label=]    mark a region of the screen
///     u [<id>]                           unmark one, or all of them                        close a surface
///
/// A line is either complete or invisible, which is the whole reason this is the
/// right thing to put on a socket. There is no partial-value state to get wrong:
/// a half-arrived instruction is simply held in the buffer until its newline
/// lands. A JSON stream over the same socket would need a repairing parser and
/// could still show a number that is about to change.
public enum LineParseError: Error, CustomStringConvertible {
    case unknownVerb(String, line: String)
    case malformed(String, line: String)

    public var description: String {
        switch self {
        case .unknownVerb(let verb, let line):
            return "Unknown verb \"\(verb)\" in: \(line)"
        case .malformed(let why, let line):
            return "\(why) in: \(line)"
        }
    }
}

public enum LineParser {
    /// Split a line into whitespace-separated tokens, keeping quoted strings and
    /// bracketed JSON intact. Written by hand because splitting cannot see
    /// quoting, and a regex that can is worse to read than the loop.
    static func tokenize(_ line: String) -> [String] {
        var out: [String] = []
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            while i < chars.count, chars[i] == " " || chars[i] == "\t" { i += 1 }
            if i >= chars.count { break }

            let start = i
            var depth = 0
            var inString = false
            var escaped = false

            while i < chars.count {
                let ch = chars[i]
                if inString {
                    if escaped { escaped = false }
                    else if ch == "\\" { escaped = true }
                    else if ch == "\"" { inString = false }
                } else if ch == "\"" {
                    inString = true
                } else if ch == "{" || ch == "[" {
                    depth += 1
                } else if ch == "}" || ch == "]" {
                    depth -= 1
                } else if (ch == " " || ch == "\t") && depth == 0 {
                    break
                }
                i += 1
            }

            if inString || depth != 0 {
                // Unbalanced: hand back the rest as one token and let the caller
                // produce a useful error rather than silently truncating.
                out.append(String(chars[start...]))
                return out
            }
            out.append(String(chars[start..<i]))
        }
        return out
    }

    /// Find the first `=` outside a quoted string, so `label="a=b"` works.
    static func splitPair(_ token: String) -> (String, String)? {
        var inString = false
        var escaped = false
        for (i, ch) in token.enumerated() {
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "=" {
                let idx = token.index(token.startIndex, offsetBy: i)
                return (
                    String(token[token.startIndex..<idx]),
                    String(token[token.index(after: idx)...])
                )
            }
        }
        return nil
    }

    static func parseValue(_ raw: String) -> PropValue {
        if raw.hasPrefix("@") {
            return .binding(DataBinding(pointer: String(raw.dropFirst())))
        }
        if raw.hasPrefix("!") {
            return .literal(.string(String(raw.dropFirst())))
        }
        if raw == "true" { return .literal(.bool(true)) }
        if raw == "false" { return .literal(.bool(false)) }
        if raw == "null" { return .literal(.null) }

        if let first = raw.first, first == "\"" || first == "{" || first == "[" {
            if let json = JSONDecoding.parse(raw) {
                if let computed = Computed.from(json) { return .computed(computed) }
                // `{"$bind":"/path"}` as well as `@/path`.
                //
                // `@` is the short form and the one to write, but the object
                // form is what the JSON spec format uses and models reach for it
                // constantly by analogy with `$count`. Rejecting it produced the
                // worst possible failure: the prop parsed as a perfectly valid
                // object literal, the component drew nothing, and nobody was
                // told anything.
                if let object = json.objectValue,
                   let pointer = object["$bind"]?.stringValue,
                   object.count == 1 {
                    return .binding(DataBinding(pointer: pointer))
                }
                return .literal(json)
            }
        }
        if let first = raw.first, first.isNumber || first == "-", let n = Double(raw) {
            return .literal(.number(n))
        }
        // A bare word is a string. The model reaches for this constantly and
        // quoting every enum value would cost tokens for nothing.
        return .literal(.string(raw))
    }

    /// Parse one complete line. Returns nil for blanks and comments.
    public static func parse(_ line: String) throws -> Op? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }

        let tokens = tokenize(trimmed)
        guard let verb = tokens.first else { return nil }

        switch verb {
        case "c":
            guard tokens.count >= 3 else {
                throw LineParseError.malformed("`c` needs an id and a type", line: trimmed)
            }
            let id = tokens[1]
            let type = tokens[2]
            // Component types are PascalCase by catalog rule, so requiring it
            // stops an English sentence beginning with "c " from parsing.
            guard let firstChar = type.first, firstChar.isUppercase else {
                throw LineParseError.malformed("type must be PascalCase", line: trimmed)
            }
            var props: [String: PropValue] = [:]
            for token in tokens.dropFirst(3) {
                guard let (key, raw) = splitPair(token) else {
                    throw LineParseError.malformed("expected key=value", line: trimmed)
                }
                props[key] = parseValue(raw)
            }
            return .component(ComponentNode(id: id, type: type, props: props))

        case ">":
            guard tokens.count >= 2 else {
                throw LineParseError.malformed("`>` needs a parent id", line: trimmed)
            }
            return .children(id: tokens[1], children: Array(tokens.dropFirst(2)))

        case "d":
            guard tokens.count >= 2 else {
                throw LineParseError.malformed("`d` needs a pointer", line: trimmed)
            }
            let path = tokens[1]
            guard path.hasPrefix("/") else {
                throw LineParseError.malformed("`d` needs a JSON Pointer", line: trimmed)
            }
            let rest = tokens.dropFirst(2).joined(separator: " ")
            if rest.isEmpty { return .data(path: path, value: nil) }
            guard case .literal(let json) = parseValue(rest) else {
                return .data(path: path, value: nil)
            }
            return .data(path: path, value: json)

        case "@":
            guard tokens.count >= 2 else {
                throw LineParseError.malformed("`@` needs a surface name", line: trimmed)
            }
            var region: Region?
            var width: Double?
            var urgency: Urgency?
            var chrome: Chrome?
            var life: Double?
            for token in tokens.dropFirst(2) {
                guard let (key, raw) = splitPair(token) else { continue }
                let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if key == "at" { region = Region(rawValue: value) }
                if key == "w" || key == "width" { width = Double(value) }
                if key == "urgency" { urgency = Urgency(rawValue: value) }
                if key == "chrome" { chrome = Chrome(rawValue: value) }
                if key == "life" { life = Double(value) }
            }
            return .surface(
                id: tokens[1], region: region, width: width,
                urgency: urgency, chrome: chrome, life: life)

        case "-":
            guard tokens.count == 2 else {
                throw LineParseError.malformed("`-` takes exactly one surface name", line: trimmed)
            }
            return .close(id: tokens[1])

        case "m":
            // `m <id> <x> <y> <w> <h> [label="..."] [tone=warn] [life=30]`
            //
            // Absolute screen points with a top-left origin, because that is
            // what a screenshot and a window query both give you and converting
            // in two places is how a marker ends up in the wrong corner.
            guard tokens.count >= 6,
                  let x = Double(tokens[2]), let y = Double(tokens[3]),
                  let width = Double(tokens[4]), let height = Double(tokens[5])
            else {
                throw LineParseError.malformed(
                    "`m` needs an id and four numbers", line: trimmed)
            }
            var label = ""
            var tone: String?
            var life: Double?
            for token in tokens.dropFirst(6) {
                guard let (key, raw) = splitPair(token) else { continue }
                let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                switch key {
                case "label": label = value
                case "tone": tone = value
                case "life": life = Double(value)
                default: break
                }
            }
            return .mark(
                id: tokens[1],
                rect: CGRect(x: x, y: y, width: width, height: height),
                label: label, tone: tone, life: life)

        case "u":
            return .unmark(id: tokens.count >= 2 ? tokens[1] : "")

        case "p":
            // `p thinking`, `p hearing amp=0.4`, `p dormant`.
            guard tokens.count >= 2 else {
                throw LineParseError.malformed("`p` needs a state", line: trimmed)
            }
            guard let presence = Presence(rawValue: tokens[1]) else {
                throw LineParseError.malformed(
                    "unknown presence state \(tokens[1])", line: trimmed)
            }
            var amplitude: Double?
            for token in tokens.dropFirst(2) {
                guard let (key, raw) = splitPair(token) else { continue }
                if key == "amp" { amplitude = Double(raw) }
            }
            return .presence(presence, amplitude: amplitude)

        case "r":
            guard tokens.count == 2 else {
                throw LineParseError.malformed("`r` takes exactly one id", line: trimmed)
            }
            return .root(id: tokens[1])

        default:
            throw LineParseError.unknownVerb(verb, line: trimmed)
        }
    }
}

/// Incremental line splitter. Feed it arbitrary bytes off a socket; it yields
/// only complete lines and holds the partial tail.
public struct LineBuffer: Sendable {
    private var buffer = ""

    public init() {}

    public mutating func push(_ chunk: String) -> [String] {
        buffer += chunk
        var lines: [String] = []
        while let idx = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[buffer.startIndex..<idx]))
            buffer = String(buffer[buffer.index(after: idx)...])
        }
        return lines
    }

    /// Flush a trailing line with no newline. Call once, at end of stream.
    public mutating func flush() -> String? {
        guard !buffer.trimmingCharacters(in: .whitespaces).isEmpty else {
            buffer = ""
            return nil
        }
        let rest = buffer
        buffer = ""
        return rest
    }

    public var pending: String { buffer }
}

/// Minimal JSON decoding into our own value type.
enum JSONDecoding {
    static func parse(_ text: String) -> JSON? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard
            let any = try? JSONSerialization.jsonObject(
                with: data, options: [.fragmentsAllowed])
        else { return nil }
        return convert(any)
    }

    static func convert(_ any: Any) -> JSON {
        switch any {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            // NSNumber does not distinguish bool from number, so check the type
            // encoding before falling through to a double.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let a as [Any]: return .array(a.map(convert))
        case let o as [String: Any]: return .object(o.mapValues(convert))
        default: return .null
        }
    }
}

extension Computed {
    /// Recognise a computed expression inside a decoded JSON object.
    static func from(_ json: JSON) -> Computed? {
        guard let obj = json.objectValue else { return nil }
        if let path = obj["$count"]?.stringValue {
            if let whereObj = obj["where"]?.objectValue,
               let field = whereObj["field"]?.stringValue {
                return .count(path: path, whereField: field, equals: whereObj["equals"])
            }
            return .count(path: path, whereField: nil, equals: nil)
        }
        if let path = obj["$sum"]?.stringValue, let field = obj["field"]?.stringValue {
            return .sum(path: path, field: field)
        }
        if let path = obj["$avg"]?.stringValue, let field = obj["field"]?.stringValue {
            return .avg(path: path, field: field)
        }
        return nil
    }
}
