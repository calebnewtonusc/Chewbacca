import AppKit
import SwiftUI

/// The answer's text, as blocks.
///
/// The model writes Markdown whether or not it is asked to, and a paragraph
/// with `**` in it is a paragraph that was never edited. This is the small
/// subset worth drawing: paragraphs, headings, bullet and numbered lists,
/// quotes, fenced code, rules and pipe tables. Anything else stays as it
/// came, which is readable, rather than being dropped, which is not.
enum Prose {
    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bullets([String])
        case numbered([String])
        case quote(String)
        case code(language: String, text: String)
        case rule
        case table(header: [String], rows: [[String]])
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [String] = []
        var quote: [String] = []
        var table: [[String]] = []
        var code: (language: String, lines: [String])?

        func flush() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.paragraph(joined)) }
            paragraph = []
            if !bullets.isEmpty { out.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { out.append(.numbered(numbered)); numbered = [] }
            if !quote.isEmpty { out.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            if !table.isEmpty {
                out.append(.table(header: table[0], rows: Array(table.dropFirst())))
                table = []
            }
        }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if let open = code {
                    out.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = (String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces), [])
                }
                continue
            }
            if code != nil {
                code?.lines.append(raw)
                continue
            }
            if line.isEmpty {
                flush()
                continue
            }
            if let heading = headingLevel(line) {
                flush()
                out.append(.heading(level: heading.level, text: heading.text))
                continue
            }
            if isRule(line) {
                flush()
                out.append(.rule)
                continue
            }
            if line.hasPrefix("|"), line.hasSuffix("|") {
                let cells = line.dropFirst().dropLast().components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // The separator row under the header says nothing.
                if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" } && !$0.isEmpty }) {
                    continue
                }
                if bullets.isEmpty, numbered.isEmpty, quote.isEmpty, paragraph.isEmpty {
                    table.append(cells)
                    continue
                }
            }
            if let item = bulletItem(line) {
                if !paragraph.isEmpty || !numbered.isEmpty || !quote.isEmpty || !table.isEmpty { flush() }
                bullets.append(item)
                continue
            }
            if let item = numberedItem(line) {
                if !paragraph.isEmpty || !bullets.isEmpty || !quote.isEmpty || !table.isEmpty { flush() }
                numbered.append(item)
                continue
            }
            if line.hasPrefix(">") {
                if !paragraph.isEmpty || !bullets.isEmpty || !numbered.isEmpty || !table.isEmpty { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            // A line that continues a list item wraps into it.
            if !bullets.isEmpty { bullets[bullets.count - 1] += " " + line; continue }
            if !numbered.isEmpty { numbered[numbered.count - 1] += " " + line; continue }
            if !quote.isEmpty { quote.append(line); continue }
            if !table.isEmpty { flush() }
            paragraph.append(line)
        }
        if let open = code {
            out.append(.code(language: open.language, text: open.lines.joined(separator: "\n")))
        }
        flush()
        return out
    }

    private static func headingLevel(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard level > 0, rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ line: String) -> Bool {
        let bare = line.replacingOccurrences(of: " ", with: "")
        guard bare.count >= 3 else { return false }
        return Set(bare).count == 1 && "-*_".contains(bare.first!)
    }

    private static func bulletItem(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ ", "• "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func numberedItem(_ line: String) -> String? {
        var digits = 0
        var rest = Substring(line)
        while let first = rest.first, first.isNumber, digits < 3 {
            digits += 1
            rest = rest.dropFirst()
        }
        guard digits > 0, rest.first == "." || rest.first == ")" else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    /// Inline Markdown, line breaks kept. A run that fails to parse is
    /// shown as it came rather than not at all.
    static func styled(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// One block drawn. `caret` puts the writing cursor after the text, for the
/// last block of an answer still arriving.
struct ProseBlockView: View {
    let block: Prose.Block
    var caret = false

    var body: some View {
        switch block {
        case .paragraph(let text):
            ProseText(text: text, caret: caret)

        case .heading(let level, let text):
            Text(Prose.styled(text))
                .font(.system(size: level <= 2 ? 15 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(HUD.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(HUD.accent.opacity(0.85))
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        ProseText(text: item, caret: caret && index == items.count - 1)
                    }
                }
            }
            .padding(.leading, 4)

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(HUD.accent.opacity(0.9))
                            .frame(minWidth: 18, alignment: .trailing)
                        ProseText(text: item, caret: caret && index == items.count - 1)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(HUD.accent.opacity(0.6))
                    .frame(width: 2)
                ProseText(text: text, caret: caret, tone: HUD.dim)
            }
            .padding(.vertical, 2)

        case .code(let language, let text):
            CodeBlock(language: language, text: text)

        case .rule:
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .table(let header, let rows):
            ProseTable(header: header, rows: rows)
        }
    }
}

/// A run of inline Markdown, with the writing caret after it while the
/// answer is still arriving.
struct ProseText: View {
    let text: String
    var caret = false
    var tone: Color = HUD.ink

    var body: some View {
        if caret {
            // A hard blink at two a second, off the clock rather than off
            // state, so a hundred re-layouts of a growing answer do not
            // each restart it.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                (Text(Prose.styled(text))
                    + Text("\u{258D}").foregroundStyle(HUD.accent.opacity(on ? 0.95 : 0.25)))
                    .font(.system(size: 13))
                    .foregroundStyle(tone)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(Prose.styled(text))
                .font(.system(size: 13))
                .foregroundStyle(tone)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Fenced code: its language, a copy button, and the text in monospace on
/// a plate that scrolls sideways rather than wrapping a long line.
struct CodeBlock: View {
    let language: String
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HUD.faint)
                    .textCase(.lowercase)
                Spacer()
                IconButton(
                    symbol: copied ? "checkmark" : "doc.on.doc",
                    help: copied ? "Copied" : "Copy the code", size: 20, action: copy)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.04))
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(HUD.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(10)
            }
        }
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private func copy() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

/// A pipe table as a grid: header in weight, a rule under it, rows zebra'd
/// faintly so a wide one can be read across.
struct ProseTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        let columns = max(header.count, rows.map(\.count).max() ?? 0)
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                ForEach(0..<columns, id: \.self) { column in
                    Text(Prose.styled(column < header.count ? header[column] : ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HUD.dim)
                        .padding(.vertical, 6)
                }
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                .gridCellColumns(columns)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        Text(Prose.styled(column < row.count ? row[column] : ""))
                            .font(.system(size: 12))
                            .foregroundStyle(HUD.ink)
                            .textSelection(.enabled)
                            .padding(.vertical, 5)
                    }
                }
                .background(index % 2 == 1 ? Color.white.opacity(0.03) : Color.clear)
            }
        }
        .padding(.horizontal, 10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
