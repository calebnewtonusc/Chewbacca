import AppKit
import SwiftUI

/// One turn of the conversation: what the person asked, or what was
/// answered.
public struct ChatTurn: Identifiable, Equatable, Sendable {
    public enum Role: Sendable {
        case person, assistant
    }

    public let id: Int
    public let role: Role
    public var text: String
    /// False while an answer is still being written.
    public var done: Bool
    /// Whether the request was typed rather than spoken. Carried so the
    /// panel can say which, and so a written reply to a typed request is
    /// not read aloud by anything downstream.
    public var typed: Bool

    public init(id: Int, role: Role, text: String, done: Bool, typed: Bool) {
        self.id = id
        self.role = role
        self.text = text
        self.done = done
        self.typed = typed
    }
}

/// The conversation, as a window of its own.
///
/// The pill is two lines of glass and that is the right size for a
/// subtitle. It is the wrong size for a five-paragraph answer, for copying
/// an answer into a document, and for typing a request when speaking is not
/// an option. Clicking the pill opens this; it is what the pill expands
/// into.
///
/// A separate panel rather than a view on the glass, and the reason is the
/// text field. The glass must never become key: the command bar is the
/// precedent here, an `NSPanel` that takes key, activates the app for the
/// caret, and hands focus back when it goes. This does the same, so typing
/// and Command-C both work without teaching the overlay a new trick.
@MainActor
public final class ChatWindow: NSPanel {
    private let onDismiss: () -> Void

    /// 520 wide: 440 is the pill and this is the pill grown, not a second
    /// product. Sixty characters of 13pt at this width, which is a
    /// paragraph's measure. Guessed, never measured.
    public static let width: CGFloat = 520
    /// Tall enough for an exchange, never more than the visible height
    /// leaves room for, because a chat that runs off the screen hides the
    /// one thing being read: the newest line, at the bottom.
    public static func height(on screen: NSScreen?) -> CGFloat {
        let visible = screen?.visibleFrame.height ?? 800
        return min(600, max(320, visible * 0.55))
    }

    public init(
        model: OverlayModel,
        onSubmit: @escaping (String) -> Void,
        onStop: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height(on: OverlayWindow.active)),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false)

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isFloatingPanel = true
        // Floating, not modal: it stays over the work and gets out of the
        // way of a dialog, which is what a chat beside the work should do.
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        minSize = NSSize(width: 380, height: 260)

        contentView = NSHostingView(
            rootView: ChatPanel(
                model: model,
                onSubmit: onSubmit,
                onStop: onStop,
                onClose: { [weak self] in self?.dismiss() }))
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Where the pill was: bottom centre of the screen the pointer is on,
    /// the same lift above the Dock, so opening reads as the pill growing
    /// rather than a second thing arriving elsewhere.
    public func present() {
        if let screen = OverlayWindow.active {
            let visible = screen.visibleFrame
            let size = frame.size
            setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.minY + PillView.pillLift))
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func dismiss() {
        orderOut(nil)
        onDismiss()
    }

    public override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}

/// What the conversation looks like.
struct ChatPanel: View {
    let model: OverlayModel
    let onSubmit: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hudOffscreen) private var offscreen

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SurfaceChrome.radius, style: .continuous)
    }

    private var working: Bool { model.pill.phase == .working }

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            transcript
            rule
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The cards' frost, not the pill's clear glass: paragraphs need a
        // ground, and a page of white text over a white document is the
        // failure the cards' wash was tuned against.
        .modifier(SurfaceChrome(chrome: .card, lit: true))
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private var rule: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            PresenceRing(presence: model.presence, amplitude: model.amplitude)
            Text("Chewbacca")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(HUD.ink)
            Text(status)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HUD.faint)
                .lineLimit(1)
                .id(status)
                .transition(.opacity)
            Spacer(minLength: 8)
            IconButton(symbol: "trash", help: "Clear the conversation") { model.clearChat() }
                .disabled(model.turns.isEmpty)
            IconButton(symbol: "chevron.down", help: "Back to the pill", action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(Motion.fade(0.18, reduced: reduceMotion), value: status)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Not lazy: the conversation is capped at two hundred
                // turns, and a lazy stack under a bottom anchor lays out
                // from a scroll position it has not measured yet.
                VStack(alignment: .leading, spacing: 14) {
                    if model.turns.isEmpty {
                        empty
                    }
                    ForEach(model.turns) { turn in
                        TurnView(turn: turn, status: pending(for: turn))
                            .id(turn.id)
                    }
                    // Something to scroll to that is always last.
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(.bottom)
            // Follow the newest line as it is written. An answer that grows
            // under the fold is one the person has to chase.
            .onChange(of: model.revision) { _, _ in
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing yet")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(HUD.dim)
            Text("Hold the globe key and speak, or type below.")
                .font(.system(size: 12))
                .foregroundStyle(HUD.faint)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if offscreen {
                // `ImageRenderer` cannot draw an AppKit text field; it
                // comes out as a prohibition sign on a yellow bar. The
                // snapshot gets the field's own prompt in its place.
                Text("Ask anything")
                    .font(.system(size: 13))
                    .foregroundStyle(HUD.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField(
                    "", text: $draft, prompt: Text("Ask anything").foregroundStyle(HUD.faint),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(HUD.ink)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit(submit)
                .accessibilityLabel("Ask anything")
            }

            if working {
                IconButton(symbol: "stop.fill", help: "Stop", action: onStop)
            } else {
                IconButton(symbol: "arrow.up", help: "Send", prominent: true, action: submit)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func submit() {
        let asked = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }
        draft = ""
        onSubmit(asked)
    }

    /// The line under an answer still being written: the pill's breadcrumb,
    /// which is what the assistant is doing right now.
    private func pending(for turn: ChatTurn) -> String? {
        guard turn.role == .assistant, !turn.done else { return nil }
        guard turn.id == model.turns.last(where: { $0.role == .assistant })?.id else { return nil }
        let line = model.pill.saying
        return line.isEmpty ? "Thinking" : line
    }

    private var status: String {
        switch model.presence {
        case .dormant: return model.pill.queued > 0 ? "\(model.pill.queued) waiting" : ""
        case .attentive: return "Listening"
        case .hearing: return "Hearing you"
        case .speaking: return "Speaking"
        case .thinking: return "Thinking"
        case .acting: return "Working"
        case .done: return "Done"
        case .attention: return "Needs you"
        case .failed: return "Did not finish"
        }
    }
}

/// One turn drawn.
///
/// The person's words sit right, in a bubble the accent's colour at low
/// opacity, because that is the shape every messaging app has taught. The
/// answer sits left with no bubble at all: it is the longer text, and a
/// bubble round three paragraphs is a box, not a message.
struct TurnView: View {
    let turn: ChatTurn
    /// What is being done for this turn right now, while it is open.
    let status: String?

    @State private var hovering = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch turn.role {
        case .person:
            HStack {
                Spacer(minLength: 56)
                Text(turn.text)
                    .font(.system(size: 13))
                    .foregroundStyle(HUD.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        HUD.accent.opacity(0.20),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(HUD.accent.opacity(0.25), lineWidth: 1)
                    }
            }
            .accessibilityLabel((turn.typed ? "You typed " : "You said ") + turn.text)

        case .assistant:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(Prose.blocks(turn.text).enumerated()), id: \.offset) { _, block in
                    ProseBlockView(block: block)
                }
                if let status {
                    HStack(spacing: 6) {
                        Working()
                        Text(status)
                            .font(.system(size: 12))
                            .foregroundStyle(HUD.faint)
                            .lineLimit(1)
                            .id(status)
                            .transition(.opacity)
                    }
                    .animation(Motion.fade(0.18, reduced: reduceMotion), value: status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 28)
            .overlay(alignment: .topTrailing) {
                if turn.done, !turn.text.isEmpty {
                    IconButton(
                        symbol: copied ? "checkmark" : "doc.on.doc",
                        help: copied ? "Copied" : "Copy the answer",
                        action: copy)
                    .opacity(hovering || copied ? 1 : 0)
                }
            }
            .onHover { hovering = $0 }
            .animation(Motion.fade(0.14, reduced: reduceMotion), value: hovering)
            .accessibilityElement(children: .combine)
        }
    }

    private func copy() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(turn.text, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

/// Three dots that take turns. The one animation in the panel, and it stops
/// the moment the answer closes.
private struct Working: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(HUD.faint)
                    .frame(width: 4, height: 4)
                    .opacity(on ? 1 : 0.3)
                    .animation(
                        Motion.repeating(
                            .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            reduced: reduceMotion),
                        value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

/// The answer's text, as paragraphs and code.
///
/// The model writes Markdown whether or not it is asked to, and a paragraph
/// with `**` in it is a paragraph that was never edited. Inline emphasis,
/// code and links are rendered; a fenced block is set in monospace on its
/// own plate. Headings and tables are not drawn specially, because the
/// prompt asks for neither and a heading that arrives anyway reads fine as
/// a short line.
enum Prose {
    enum Block: Equatable {
        case paragraph(String)
        case code(String)
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            let joined = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.paragraph(joined)) }
            paragraph = []
        }
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = code {
                    out.append(.code(open.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(line)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            } else {
                paragraph.append(line)
            }
        }
        if let open = code { out.append(.code(open.joined(separator: "\n"))) }
        flush()
        return out
    }
}

struct ProseBlockView: View {
    let block: Prose.Block

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(styled(text))
                .font(.system(size: 13))
                .foregroundStyle(HUD.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .code(let text):
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(HUD.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// Inline Markdown, line breaks kept. A paragraph that fails to parse
    /// is shown as it came rather than not at all.
    private func styled(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// A small round button with a symbol in it, the panel's one control shape.
struct IconButton: View {
    let symbol: String
    let help: String
    var prominent = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(prominent ? Color.black.opacity(0.85) : HUD.dim)
                .frame(width: 24, height: 24)
                .background(
                    prominent ? HUD.accent.opacity(hovering ? 1 : 0.9) : .white.opacity(hovering ? 0.16 : 0.08),
                    in: Circle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}
