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
    /// What was done to get an answer, one line per tool call, in order.
    /// Empty for a person's turn and for an answer that needed no tool.
    public var steps: [String]
    /// When the turn began, and when an answer closed. What the panel
    /// shows as the time on hover and the seconds next to the steps.
    public var startedAt: Date
    public var endedAt: Date?

    public init(
        id: Int, role: Role, text: String, done: Bool, typed: Bool,
        steps: [String] = [], startedAt: Date = Date(), endedAt: Date? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.done = done
        self.typed = typed
        self.steps = steps
        self.startedAt = startedAt
        self.endedAt = endedAt
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

    /// The frame it was last left at, under this key in the defaults. A
    /// panel that has been dragged beside the work should come back there.
    public static let frameName = "chewbacca.chat"
    /// Whether a saved frame was found at construction. Without one, the
    /// panel opens where the pill was.
    private let restoredFrame: Bool
    /// Whether it has been put at the pill once this session. After that a
    /// drag is respected, as long as it stays on the main display.
    private var placed = false

    public init(
        model: OverlayModel,
        onSubmit: @escaping (String) -> Void,
        onSpeak: @escaping (String) -> Void,
        onStop: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self.restoredFrame = UserDefaults.standard.string(forKey: "NSWindow Frame " + Self.frameName) != nil
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
                stage: stage,
                onSubmit: onSubmit,
                onSpeak: onSpeak,
                onStop: onStop,
                onClose: { [weak self] in self?.dismiss() }))
        if restoredFrame { setFrameUsingName(Self.frameName) }
        setFrameAutosaveName(Self.frameName)
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// Where the pill was: bottom centre of the main display, the same
    /// lift above the Dock, so opening reads as the pill growing
    /// rather than a second thing arriving elsewhere. Once it has been
    /// dragged somewhere on that display it comes back to that place
    /// instead.
    public func present() {
        if let screen = OverlayWindow.active,
           Self.needsPlacing(frame: frame, on: screen.frame, restored: restoredFrame, placed: placed) {
            let visible = screen.visibleFrame
            let size = frame.size
            setFrameOrigin(
                NSPoint(
                    x: visible.midX - size.width / 2,
                    y: visible.minY + PillView.pillLift))
        }
        placed = true
        showing += 1
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether the panel goes to the pill's spot rather than where it is.
    /// A frame is kept only while its centre is on the main display: one
    /// saved on 2026-09-20 while the glass still followed the pointer sat
    /// on the laptop screen at y=1791, below the monitor's 1440, and would
    /// have opened there on every click after the display was pinned.
    static func needsPlacing(frame: NSRect, on screen: NSRect, restored: Bool, placed: Bool) -> Bool {
        let centre = NSPoint(x: frame.midX, y: frame.midY)
        if !screen.contains(centre) { return true }
        return !restored && !placed
    }

    /// Whether the panel is grown out of the pill or folded back into it.
    let stage = ChatStage()
    /// Bumped on every present, so a fold that finishes after the panel was
    /// reopened does not take the reopened one down with it.
    private var showing = 0

    public func dismiss() {
        conceal()
        onDismiss()
    }

    /// Fold back into the pill, then leave. It opened by growing out of the
    /// pill and until 2026-09-22 closed by vanishing, and an exit that does
    /// not answer its entrance reads as a crash rather than a close.
    public func conceal() {
        guard isVisible, stage.open else { return }
        let token = showing
        withAnimation(Motion.snappy(reduced: Motion.systemReduced)) { stage.open = false }
        // The snappy spring is visually settled by about 0.25 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self, self.showing == token, !self.stage.open else { return }
            self.orderOut(nil)
        }
    }

    public override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}

/// Open or folded, shared between the window that decides and the view that
/// draws it, so the fold can run before the window goes.
@MainActor
@Observable
final class ChatStage {
    var open = false
}

/// What the conversation looks like.
struct ChatPanel: View {
    let model: OverlayModel
    var stage = ChatStage()
    let onSubmit: (String) -> Void
    let onSpeak: (String) -> Void
    let onStop: () -> Void
    let onClose: () -> Void

    @State private var draft = ""
    /// Whether the transcript follows the newest line. Off once the person
    /// scrolls up to read, on again when they reach the bottom or ask.
    @State private var following = true
    @State private var atBottom = true
    @State private var scrollMonitor: Any?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.hudOffscreen) private var offscreen

    /// What an empty panel offers, each one thing it can do from here.
    static let suggestions = [
        "What is on my calendar today?",
        "Any texts I have not answered?",
        "What am I looking at?",
    ]

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
        .environment(\.hudEnergy, model.presence.energy)
        .environment(\.colorScheme, .dark)
        // The pill growing into the panel. The panel opens standing where
        // the pill stood, so it starts as a capsule the pill's size at the
        // bottom and opens out to its own frame; the words fade in once
        // there is room for them.
        .modifier(GrowFromPill(progress: stage.open || offscreen ? 1 : 0, from: model.pillSize))
        .onChange(of: model.chatOpenings, initial: true) { _, _ in enter() }
        .onAppear { focused = true }
        .onExitCommand { onClose() }
    }

    private func enter() {
        guard !offscreen else { return }
        stage.open = false
        Task { @MainActor in
            withAnimation(Motion.smooth(reduced: reduceMotion)) { stage.open = true }
            focused = true
        }
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
                .modifier(Shimmer(on: busy && !reduceMotion))
                .id(status)
                .transition(.opacity)
            Spacer(minLength: 8)
            Toggle(
                isOn: Binding(
                    get: { model.longAnswersWritten },
                    set: { model.setLongAnswersWritten($0) })
            ) {
                Text("Speech off for long answers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HUD.faint)
                    .lineLimit(1)
            }
            .toggleStyle(SwitchStyle())
            .help(
                "On: a long answer is written here and the voice says one line pointing at it. "
                + "Off: every answer is read out in full.")
            IconButton(symbol: "trash", help: "Clear the conversation") { model.clearChat() }
                .disabled(model.turns.isEmpty)
            IconButton(symbol: "chevron.down", help: "Back to the hyper bar", action: onClose)
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
                VStack(alignment: .leading, spacing: 16) {
                    if model.turns.isEmpty {
                        empty
                    }
                    ForEach(model.turns) { turn in
                        TurnView(
                            turn: turn,
                            live: live(turn),
                            status: pending(for: turn),
                            isLast: turn.id == model.turns.last?.id,
                            onSpeak: { onSpeak(turn.text) },
                            onRegenerate: { regenerate(turn) },
                            onEdit: { edit(turn) })
                        .id(turn.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity))
                    }
                    // Something to scroll to that is always last, and that
                    // says whether the bottom is in view.
                    Color.clear.frame(height: 1).id("end")
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: EndVisible.self,
                                    value: geometry.frame(in: .named("transcript")).maxY)
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .animation(Motion.smooth(reduced: reduceMotion), value: model.turns.count)
            }
            .coordinateSpace(name: "transcript")
            .scrollIndicators(.automatic)
            .defaultScrollAnchor(.bottom)
            .overlay(alignment: .bottom) {
                if !following, !model.turns.isEmpty {
                    Latest {
                        following = true
                        withAnimation(Motion.smooth(reduced: reduceMotion)) {
                            proxy.scrollTo("end", anchor: .bottom)
                        }
                    }
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.snappy(reduced: reduceMotion), value: following)
            .background {
                GeometryReader { geometry in
                    Color.clear.onPreferenceChange(EndVisible.self) { maxY in
                        // Within a line of the bottom counts as there.
                        let near = maxY <= geometry.size.height + 24
                        if near != atBottom { atBottom = near }
                        if near { following = true }
                    }
                }
            }
            // Follow the newest line as it is written. An answer that grows
            // under the fold is one the person has to chase, unless they
            // scrolled up on purpose, in which case it waits.
            .onChange(of: model.revision) { _, _ in
                guard following else { return }
                proxy.scrollTo("end", anchor: .bottom)
            }
            .onAppear { watchScrolling() }
            .onDisappear { stopWatching() }
        }
    }

    /// The person scrolling up is the one signal that they want to read
    /// rather than follow. The wheel says so directly; the bottom marker
    /// alone cannot, because a growing answer pushes it out of view too.
    private func watchScrolling() {
        guard !offscreen, scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.window is ChatWindow, event.scrollingDeltaY > 0 {
                Task { @MainActor in following = false }
            }
            return event
        }
    }

    private func stopWatching() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(HUD.ink)
                Text("Hold \(PushKey.chosen.title) and speak, or type below. Anything on your Mac, or anything at all.")
                    .font(.system(size: 12))
                    .foregroundStyle(HUD.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlowLayout(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Chip(text: suggestion) { onSubmit(suggestion) }
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Still up"
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    IconButton(symbol: "stop.fill", help: "Stop", tint: HUD.bad, action: onStop)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    IconButton(symbol: "arrow.up", help: "Send", prominent: true, action: submit)
                        .disabled(!canSend)
                        .keyboardShortcut(.return, modifiers: .command)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(Motion.snappy(reduced: reduceMotion), value: working)
            HStack(spacing: 6) {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HUD.faint.opacity(0.7))
                    .lineLimit(1)
                    .id(hint)
                    .transition(.opacity)
                Spacer()
            }
            .animation(Motion.fade(0.18, reduced: reduceMotion), value: hint)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var busy: Bool {
        model.presence == .thinking || model.presence == .acting
    }

    private var hint: String {
        if working {
            return model.pill.queued > 0
                ? "\(model.pill.queued) waiting. Return sends another, Escape closes."
                : "Return sends another and it waits its turn. Escape closes."
        }
        return "Return sends. Option-Return for a new line. Typed requests are answered in writing."
    }

    private func submit() {
        let asked = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty else { return }
        draft = ""
        following = true
        onSubmit(asked)
    }

    /// Ask the same thing again: a fresh exchange under the old one, so the
    /// first answer is still there to compare.
    private func regenerate(_ turn: ChatTurn) {
        guard let index = model.turns.firstIndex(where: { $0.id == turn.id }) else { return }
        guard let person = model.turns[..<index].last(where: { $0.role == .person }) else { return }
        following = true
        onSubmit(person.text)
    }

    /// Put the person's words back in the field to change and send again.
    private func edit(_ turn: ChatTurn) {
        draft = turn.text
        focused = true
    }

    /// Whether the answer's caret should blink: it is the open one.
    private func live(_ turn: ChatTurn) -> Bool {
        turn.role == .assistant && !turn.done && !turn.text.isEmpty
    }

    /// The line under an answer still being written: the step being taken
    /// right now, or "Thinking" before any text; nothing once the text is
    /// arriving and no tool is in use, because the caret says that.
    private func pending(for turn: ChatTurn) -> String? {
        guard turn.role == .assistant, !turn.done else { return nil }
        guard turn.id == model.turns.last(where: { $0.role == .assistant })?.id else { return nil }
        if model.pill.step, !model.pill.saying.isEmpty { return model.pill.saying }
        if turn.text.isEmpty { return model.pill.saying.isEmpty ? "Thinking" : model.pill.saying }
        return nil
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

/// Where the end of the transcript is, in the scroll view's space.
private struct EndVisible: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// The way back down, for a transcript scrolled up while an answer grows.
struct Latest: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text("Latest")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(HUD.ink)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.black.opacity(hovering ? 0.62 : 0.5), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .help("Back to the newest line")
    }
}

/// Chips on as many rows as they need. `HStack` would clip the third one
/// at the panel's narrowest width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return place(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = place(in: bounds.width, subviews: subviews)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func place(in width: CGFloat, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}

/// The conversation panel opening out of the pill.
///
/// A mask, not a scale: scaling the panel from the pill's size would squash
/// its text into a smear on the way up, and a mask shows the glass growing
/// with the words already in place behind it. It was a 0.96 scale and a fade
/// until 2026-09-22, which read as a second thing arriving rather than the
/// pill becoming the panel.
nonisolated struct GrowFromPill: ViewModifier, Animatable {
    var progress: Double
    /// The pill as it was last measured, or `fallback` if it never was.
    var from: CGSize = .zero

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// The pill at one line. Its width is `PillView.maxWidth` at most and
    /// usually less, so this is the size a person has seen it at most.
    /// Guessed, never measured.
    static let fallback = CGSize(width: 320, height: 34)
    /// How far past the panel the mask ends once open, so the glass's own
    /// shadow is not cut off at the window's edge by the thing revealing it.
    static let spill: CGFloat = 40

    func body(content: Content) -> some View {
        let p = min(max(progress, 0), 1)
        let pill = from == .zero ? Self.fallback : from
        return content
            // Nothing readable until the capsule is most of the way open.
            .opacity(min(1, max(0, (p - 0.15) / 0.5)))
            .mask {
                GeometryReader { proxy in
                    let full = proxy.size
                    let width = lerp(pill.width, full.width + Self.spill * 2, p)
                    let height = lerp(pill.height, full.height + Self.spill * 2, p)
                    RoundedRectangle(
                        cornerRadius: lerp(pill.height / 2, SurfaceChrome.radius, p),
                        style: .continuous)
                        .frame(width: width, height: height)
                        .position(
                            x: full.width / 2,
                            // Pinned to the bottom, where the pill was, until
                            // the spill takes it past the edge.
                            y: full.height - height / 2 + Self.spill * p)
                }
            }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}
