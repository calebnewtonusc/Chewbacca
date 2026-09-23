import AppKit
import SwiftUI

/// One turn drawn.
///
/// The person's words sit right, in a bubble the accent's colour at low
/// opacity, because that is the shape every messaging app has taught. The
/// answer sits left with no bubble at all: it is the longer text, and a
/// bubble round three paragraphs is a box, not a message. Under each, on
/// hover, the time and what can be done with it.
struct TurnView: View {
    let turn: ChatTurn
    /// The answer is still arriving: the caret blinks after its last line.
    let live: Bool
    /// What is being done for this turn right now, while it is open.
    let status: String?
    /// The newest answer keeps its actions visible; older ones show them on
    /// hover, which is what keeps a long conversation quiet.
    let isLast: Bool
    let onSpeak: () -> Void
    let onRegenerate: () -> Void
    let onEdit: () -> Void

    @State private var hovering = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch turn.role {
        case .person: person
        case .assistant: assistant
        }
    }

    private var person: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(turn.text)
                .font(.system(size: 13))
                .foregroundStyle(HUD.ink)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    HUD.accent.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(HUD.accent.opacity(0.28), lineWidth: 1)
                }
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                Text(turn.typed ? "typed" : "said")
                    .foregroundStyle(HUD.faint.opacity(0.8))
                TimeLabel(date: turn.startedAt)
                IconButton(symbol: "pencil", help: "Edit and send again", size: 20, action: onEdit)
                IconButton(
                    symbol: copied ? "checkmark" : "doc.on.doc",
                    help: copied ? "Copied" : "Copy", size: 20, action: copy)
            }
            .font(.system(size: 10, weight: .medium))
            .opacity(hovering ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 56)
        .onHover { hovering = $0 }
        .animation(Motion.hover(reduced: reduceMotion), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((turn.typed ? "You typed " : "You said ") + turn.text)
    }

    private var assistant: some View {
        let blocks = Prose.blocks(turn.text)
        return VStack(alignment: .leading, spacing: 8) {
            if !turn.steps.isEmpty || status != nil {
                StepsView(
                    steps: turn.steps, status: status, live: !turn.done,
                    startedAt: turn.startedAt, endedAt: turn.endedAt)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                ProseBlockView(block: block, caret: live && index == blocks.count - 1)
            }
            if turn.done, !turn.text.isEmpty {
                HStack(spacing: 4) {
                    TimeLabel(date: turn.endedAt ?? turn.startedAt)
                    IconButton(
                        symbol: copied ? "checkmark" : "doc.on.doc",
                        help: copied ? "Copied" : "Copy the answer", size: 20, action: copy)
                    IconButton(symbol: "speaker.wave.2", help: "Read it aloud", size: 20, action: onSpeak)
                    if isLast {
                        IconButton(symbol: "arrow.clockwise", help: "Ask again", size: 20, action: onRegenerate)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .padding(.top, 2)
                .opacity(hovering || isLast ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 20)
        .onHover { hovering = $0 }
        .animation(Motion.hover(reduced: reduceMotion), value: hovering)
        .accessibilityElement(children: .combine)
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

/// When, in the small type the actions use.
struct TimeLabel: View {
    let date: Date

    var body: some View {
        Text(date, format: .dateTime.hour().minute())
            .foregroundStyle(HUD.faint.opacity(0.8))
            .padding(.trailing, 2)
    }
}

/// What was done to get the answer: the live step while it is being done,
/// with the clock, and the list afterwards behind a disclosure.
struct StepsView: View {
    let steps: [String]
    let status: String?
    let live: Bool
    let startedAt: Date
    let endedAt: Date?

    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(Motion.snappy(reduced: reduceMotion)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if live {
                        Working()
                        Text(status ?? "Thinking")
                            .modifier(Shimmer(on: !reduceMotion))
                            .id(status)
                            .transition(.opacity)
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            let elapsed = Int(max(0, context.date.timeIntervalSince(startedAt)))
                            Text(Duration.seconds(elapsed), format: .time(pattern: .minuteSecond))
                                .monospacedDigit()
                                .foregroundStyle(HUD.faint.opacity(0.7))
                        }
                    } else {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(HUD.good.opacity(0.9))
                        Text(summary)
                    }
                    if !steps.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                            .foregroundStyle(HUD.faint)
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(HUD.dim)
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(steps.isEmpty)
            .animation(Motion.fade(0.18, reduced: reduceMotion), value: status)

            if open, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(HUD.faint.opacity(0.6)).frame(width: 3, height: 3)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(step)
                                .font(.system(size: 11))
                                .foregroundStyle(HUD.faint)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.leading, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let seconds = Int(max(0, (endedAt ?? startedAt).timeIntervalSince(startedAt)))
        let count = steps.count == 1 ? "1 step" : "\(steps.count) steps"
        return seconds > 0 ? "\(count) in \(seconds)s" : count
    }
}

/// A band of light crossing the text, for a line that means "in progress".
/// The one animation that runs while nothing else moves, and it is off
/// under Reduce Motion because it never stops on its own.
struct Shimmer: ViewModifier {
    let on: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        if on {
            content
                .overlay {
                    GeometryReader { proxy in
                        let width = proxy.size.width
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.75), location: 0.5),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(width, 1) * 0.8)
                            .offset(x: -width * 0.8 + phase * width * 1.8)
                    }
                    .mask(content)
                }
                .onAppear {
                    // A sweep that never ends is movement that never ends.
                    guard !Motion.systemReduced else { return }
                    withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        } else {
            content
        }
    }
}

/// Three dots that take turns. It stops the moment the answer closes.
struct Working: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(HUD.accent.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .opacity(on ? 1 : 0.25)
                    .scaleEffect(on ? 1 : 0.8)
                    .animation(
                        Motion.repeating(
                            .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.18),
                            reduced: reduceMotion),
                        value: on)
            }
        }
        .onAppear { on = true }
        .accessibilityHidden(true)
    }
}

/// A small round button with a symbol in it, the panel's one control shape.
/// The symbol swaps with a morph rather than a cut, and the button gives
/// under the pointer, which is most of what "feels native" means here.
struct IconButton: View {
    let symbol: String
    let help: String
    var prominent = false
    var tint: Color?
    var size: CGFloat = 24
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size < 24 ? 9 : 10, weight: .bold))
                .foregroundStyle(ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(fill, in: Circle())
        }
        .buttonStyle(Press())
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(Motion.hover(reduced: Motion.systemReduced), value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }

    private var ink: Color {
        if prominent { return .black.opacity(0.85) }
        if let tint { return tint }
        return hovering ? HUD.ink : HUD.dim
    }

    private var fill: Color {
        if prominent { return HUD.accent.opacity(hovering ? 1 : 0.9) }
        if let tint { return tint.opacity(hovering ? 0.28 : 0.16) }
        return .white.opacity(hovering ? 0.16 : 0.08)
    }
}

/// A switch drawn here rather than `.switch`, which is an `NSSwitch`:
/// `ImageRenderer` cannot draw one and puts a prohibition sign on a
/// yellow bar in its place, so the panel's snapshot lied about its own
/// header. Drawn, it also takes the glass's accent and hover like every
/// other control on the panel.
struct SwitchStyle: ToggleStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? HUD.accent : .white.opacity(hovering ? 0.22 : 0.14))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    Circle()
                        .fill(configuration.isOn ? Color.black.opacity(0.85) : HUD.ink)
                        .padding(2)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                }
                .frame(width: 30, height: 17)
            }
        }
        .buttonStyle(Press())
        .opacity(enabled ? 1 : 0.35)
        .onHover { hovering = $0 }
        .animation(Motion.snappy(reduced: reduceMotion), value: configuration.isOn)
        .animation(Motion.hover(reduced: Motion.systemReduced), value: hovering)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// Gives under the pointer: 0.92 for the time the mouse is down.
struct Press: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.press(reduced: Motion.systemReduced), value: configuration.isPressed)
    }
}

/// One suggestion, for the empty panel.
struct Chip: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? HUD.ink : HUD.dim)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.white.opacity(hovering ? 0.12 : 0.06), in: Capsule())
                .overlay { Capsule().strokeBorder(.white.opacity(hovering ? 0.22 : 0.12), lineWidth: 1) }
        }
        .buttonStyle(Press())
        .onHover { hovering = $0 }
        .animation(Motion.hover(reduced: Motion.systemReduced), value: hovering)
    }
}
