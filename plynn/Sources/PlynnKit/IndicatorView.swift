import SwiftUI

/// Capsule geometry in one place — every size below derives from these, so
/// resizing the pill is a one-line change rather than a hunt through the view.
enum IndicatorMetrics {
    static let width: CGFloat = 168
    static let height: CGFloat = 34
    /// Collapsed width for the success check mark.
    static let compactWidth: CGFloat = 36
    /// Height of the waveform band at the capsule floor. Tall relative to the
    /// capsule on purpose — the upward-dissolve mask keeps the crests from
    /// fighting the transcript that sits over them.
    static let waveHeight: CGFloat = 22
    static let textSize: CGFloat = 11
    /// Scrolling-transcript viewport; the rest is breathing room.
    static let textWidth: CGFloat = 122
    static let inset: CGFloat = 12
    /// Slack around the capsule inside the panel, for the glass shadow.
    static let panelPadding: CGFloat = 4
    /// Gap from the bottom of the usable screen (above the Dock) to the
    /// capsule. Low enough to sit out of the way, clear enough not to look
    /// like it's falling off the edge.
    static let bottomMargin: CGFloat = 14

    // MARK: - Chewie answers
    //
    // An answer is prose, not a status word, so the capsule stops being a fixed
    // 168x34 badge and becomes a panel sized to what came back. It was clipping
    // the text top and bottom: the stage frame below and the NSPanel content
    // rect were both pinned to the badge size, so a three-line reply had one
    // line of room.
    static let answerWidth: CGFloat = 320
    /// Past this it stops being a glance and should have been a document.
    static let answerMaxHeight: CGFloat = 190
    static let answerHPadding: CGFloat = 12
    static let answerVPadding: CGFloat = 10

    /// Measured, not guessed. SwiftUI will happily lay out taller than its
    /// parent and let the window crop the difference, which is exactly the bug
    /// this replaces, so the window has to know the height before it draws.
    static func answerHeight(for text: String) -> CGFloat {
        let font =
            NSFont(descriptor:
                NSFont.systemFont(ofSize: 11, weight: .medium).fontDescriptor
                    .withDesign(.rounded) ?? NSFont.systemFont(ofSize: 11, weight: .medium)
                    .fontDescriptor,
                size: 11) ?? NSFont.systemFont(ofSize: 11, weight: .medium)
        let usable = answerWidth - answerHPadding * 2
        let box = (text as NSString).boundingRect(
            with: NSSize(width: usable, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return min(answerMaxHeight, max(height, ceil(box.height) + answerVPadding * 2))
    }
}

/// Liquid Glass arrived in macOS 26. Below it the capsule uses a translucent
/// material, which reads close enough under the rim light and sheen overlays.
private struct GlassContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

private struct CapsuleGlass: ViewModifier {
    let namespace: Namespace.ID
    /// Corner radius of the shape being glassed. Half the height is a capsule;
    /// anything less is a rounded card, which is what a multi-line answer wants.
    let radius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .glassEffect(
                    .regular.tint(.black.opacity(0.18)).interactive(),
                    in: .rect(cornerRadius: radius))
                .glassEffectID("capsule", in: namespace)
        } else {
            content.background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

/// The floating capsule: Liquid Glass surface whose bottom third is a live
/// waveform blended into the glass, centered text that fades up and slides
/// as it overflows, and a close-in checkmark on success.
struct IndicatorView: View {
    @Bindable var model: IndicatorModel
    @Namespace private var glassNS

    private var isCompact: Bool { model.phase == .done }

    var body: some View {
        GlassContainer {
            ZStack {
                // TimelineView is removed while the panel is hidden or
                // polishing. Opacity alone would leave its Canvas ticking.
                if showsWave {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        BottomWave(levels: model.levels)
                            .frame(height: IndicatorMetrics.waveHeight)
                    }
                }

                centerContent
            }
            // The capsule itself, not just the stage around it.
            //
            // This was pinned to the badge's 168x34 for every phase, so an
            // answer laid its text out at about 144 points wide and then got
            // clipped to one badge of height. The stage outside it was already
            // growing correctly, which is why the panel looked the right size
            // and the words inside it did not.
            .frame(width: capsuleSize.width, height: capsuleSize.height)
            .clipShape(shape)
            .modifier(CapsuleGlass(namespace: glassNS, radius: cornerRadius))
            // Explicit glass character — a bright rim light along the top edge
            // and a soft specular sheen, visible on any background.
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.5), location: 0),
                            .init(color: .white.opacity(0.06), location: 0.35),
                            .init(color: .white.opacity(0.18), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            .overlay(
                shape
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.10), .clear],
                            startPoint: .top, endPoint: .center))
                    .allowsHitTesting(false))
        }
        .contentShape(shape)
        .onTapGesture { model.onTap?() }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.phase)
        // Fixed-width center-aligned stage: the capsule collapses toward its
        // own center instead of snapping to the panel's leading edge.
        .frame(
            width: stageSize.width, height: stageSize.height,
            alignment: .center)
        .padding(IndicatorMetrics.panelPadding)
    }

    /// Every phase but an answer is a fixed badge. An answer is as wide and as
    /// tall as it needs to be, which is what the panel resizes itself to match.
    private var capsuleSize: CGSize {
        if isCompact {
            return CGSize(
                width: IndicatorMetrics.compactWidth, height: IndicatorMetrics.height)
        }
        if case .answer(let text) = model.phase {
            return CGSize(
                width: IndicatorMetrics.answerWidth,
                height: IndicatorMetrics.answerHeight(for: text))
        }
        return CGSize(width: IndicatorMetrics.width, height: IndicatorMetrics.height)
    }

    /// The stage is the capsule's own size: they were allowed to disagree once
    /// and the disagreement is the whole bug.
    private var stageSize: CGSize { capsuleSize }

    /// Half the height is a capsule. Capped, so a tall answer becomes a rounded
    /// card rather than a lozenge with 50-point ends.
    private var cornerRadius: CGFloat {
        min(capsuleSize.height / 2, 18)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var showsWave: Bool {
        guard model.isVisible else { return false }
        switch model.phase {
        case .recording, .meeting: return true
        case .transcribing, .done, .secure, .micUnavailable, .error, .meetingSaved,
            .thinking, .answer:
            return false
        }
    }

    @ViewBuilder
    private var centerContent: some View {
        switch model.phase {
        case .recording(let handsFree):
            HStack(spacing: 6) {
                if handsFree {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .transition(.opacity)
                }
                ScrollingPartial(text: model.partial, placeholder: "Listening…")
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .transcribing:
            PolishingLabel()
                .transition(.opacity)
        case .thinking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .tint(.white.opacity(0.8))
                Text("Chewie is on it\u{2026}")
                    .font(
                        .system(
                            size: IndicatorMetrics.textSize, weight: .medium, design: .rounded)
                    )
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
            .transition(.opacity)
        case .answer(let text):
            // Wraps rather than scrolls: the answer is the point, and a single
            // scrolling line makes you wait to read something already on screen.
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, IndicatorMetrics.answerHPadding)
                .padding(.vertical, IndicatorMetrics.answerVPadding)
                .transition(.opacity)
        case .done:
            AnimatedCheckmark()
        case .secure:
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.white.opacity(0.9))
                Text("Secure field — dictation paused")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .micUnavailable:
            HStack(spacing: 6) {
                Image(systemName: "mic.slash.fill")
                    .foregroundStyle(.white.opacity(0.9))
                Text("Microphone unavailable")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .error(let message):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow.opacity(0.95))
                    Text(message)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if !model.partial.isEmpty {
                    ScrollingPartial(text: model.partial, placeholder: "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)
        case .meeting(let elapsed):
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .modifier(RecordingPulse())
                Text("Recording meeting")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(Self.clock(elapsed))
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        case .meetingSaved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Meeting saved — writing notes…")
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, IndicatorMetrics.inset)
        }
    }
}

/// The polish stage is the app quietly working on your words — a soft light
/// sweeps once through "Polishing…", brightening each glyph a touch as it
/// passes, then settles. Monochrome and understated on purpose: the earlier
/// version lifted glyphs, cycled their hue, and threw sparkles off a glowing
/// head, which read as gaudy rather than calm. This keeps the same idea (text
/// being worked on, not a generic loading spinner) at a fraction of the
/// amplitude. Driven purely by the wall clock, so there is no state to leak.
struct PolishingLabel: View {
    private static let word = Array("Polishing…")
    /// Seconds per pass — slow and even, nothing to catch the eye.
    private static let period: Double = 2.6
    /// Wide spread means the brightening is a gentle glow, not a hot spot.
    private static let spread: Double = 3.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let count = Double(Self.word.count)
            let phase = (time.truncatingRemainder(dividingBy: Self.period)) / Self.period
            // Runs from fully before the first glyph to fully past the last,
            // so nothing pops at the wrap.
            let head = -3.0 + phase * (count + 6)

            HStack(spacing: 0) {
                ForEach(Array(Self.word.enumerated()), id: \.offset) { index, character in
                    let distance = (Double(index) - head) / Self.spread
                    let heat = max(0, exp(-distance * distance))

                    Text(String(character))
                        .font(
                            .system(
                                size: IndicatorMetrics.textSize, weight: .medium,
                                design: .rounded)
                        )
                        .foregroundStyle(.white.opacity(0.45 + 0.35 * heat))
                }
            }
        }
    }
}

/// Centered dictation text: fades up as it first appears; once it outgrows
/// the container it pins to the trailing edge, so each new word slides the
/// line left under soft gradient fades — subtle, macOS-native motion.
private struct ScrollingPartial: View {
    let text: String
    let placeholder: String
    @State private var textWidth: CGFloat = 0

    private let containerWidth: CGFloat = IndicatorMetrics.textWidth
    private var overflowing: Bool { textWidth > containerWidth }

    var body: some View {
        ZStack {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .transition(.opacity)
            } else {
                Text(text)
                    .font(.system(size: IndicatorMetrics.textSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) {
                        textWidth = $0
                    }
                    .frame(
                        width: containerWidth,
                        alignment: overflowing ? .trailing : .center)
                    .clipped()
                    .mask(
                        HStack(spacing: 0) {
                            LinearGradient(
                                colors: [.clear, .white], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 12)
                                .opacity(overflowing ? 1 : 0)
                            Rectangle()
                            LinearGradient(
                                colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 8)
                        })
                    .animation(.smooth(duration: 0.28), value: text)
                    .transition(.opacity.combined(with: .offset(y: 7)))
            }
        }
        .animation(.smooth(duration: 0.3), value: text.isEmpty)
    }
}

/// Filled, layered waves rising from the capsule floor — low opacity, masked
/// so they dissolve upward into the glass.
///
/// The texture comes from `max(0, wave)`: clamping the trough half of each
/// sine leaves crests scalloping up off a flat baseline rather than a
/// continuous ripple, and five of those at non-harmonic frequencies overlap
/// into translucent hills that never repeat. Amplitude is per-column, driven
/// by the recent-loudness history, so the hills are tall where you were loud
/// and low where you were quiet — the shape of the phrase, travelling left.
private struct BottomWave: View {
    /// Recent loudness, oldest first.
    let levels: [Float]

    private struct Layer {
        let frequency: Double
        let speed: Double
        let ampScale: Double
        let baseHeight: Double
        let opacity: Double
    }

    /// Frequencies are deliberately non-harmonic — harmonically related ones
    /// line their crests up into a visibly repeating pattern.
    private static let layers: [Layer] = [
        .init(frequency: 1.3, speed: 1.4, ampScale: 1.00, baseHeight: 3.4, opacity: 0.40),
        .init(frequency: 2.1, speed: -1.05, ampScale: 0.82, baseHeight: 2.7, opacity: 0.31),
        .init(frequency: 3.4, speed: 2.0, ampScale: 0.60, baseHeight: 2.0, opacity: 0.23),
        .init(frequency: 5.3, speed: -2.7, ampScale: 0.40, baseHeight: 1.3, opacity: 0.15),
        .init(frequency: 7.7, speed: 3.3, ampScale: 0.26, baseHeight: 0.8, opacity: 0.10),
    ]

    /// Loudness across the band, interpolated between stored points so the
    /// hills stay smooth instead of stepping at each new sample.
    private func envelope(at progress: Double) -> Double {
        guard levels.count > 1 else { return 0 }
        let position = progress * Double(levels.count - 1)
        let index = min(Int(position), levels.count - 2)
        let fraction = position - Double(index)
        return Double(levels[index]) * (1 - fraction)
            + Double(levels[index + 1]) * fraction
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // Ripples run faster while you are actually talking.
                let loudness = Double(levels.suffix(5).max() ?? 0)

                for (index, layer) in Self.layers.enumerated() {
                    var fill = Path()
                    var crest = Path()
                    let base = layer.baseHeight
                    fill.move(to: CGPoint(x: 0, y: size.height))
                    let steps = 160
                    for i in 0...steps {
                        let progress = Double(i) / Double(steps)
                        let x = size.width * progress
                        // Never fully flat, so the surface still lives in silence.
                        let drive: Double = max(0.10, envelope(at: progress))
                        // Higher floor than the original 0.10: the hills keep
                        // real body at conversational volume instead of only
                        // standing up when you get loud.
                        let amp: Double = (size.height - base) * layer.ampScale
                            * (0.22 + 0.78 * drive)
                        // Speeds up with loudness, but gently — a big swing here
                        // is what reads as "frantic" rather than "alive".
                        let speed: Double = layer.speed * (1 + loudness * 0.4)
                        let phaseA: Double = progress * layer.frequency * 2 * .pi + t * speed
                        let phaseB: Double =
                            progress * layer.frequency * 3.7 * .pi - t * speed * 0.6
                        let wave: Double = sin(phaseA) * 0.7 + sin(phaseB) * 0.3
                        let y: Double = size.height - base - max(0, wave) * amp
                        fill.addLine(to: CGPoint(x: x, y: y))
                        if i == 0 { crest.move(to: CGPoint(x: x, y: y)) }
                        else { crest.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    fill.addLine(to: CGPoint(x: size.width, y: size.height))
                    fill.closeSubpath()
                    ctx.fill(fill, with: .color(.white.opacity(layer.opacity)))
                    // Bright crest on the front hill keeps the wave legible
                    // even over a light background.
                    if index == 0 {
                        ctx.stroke(
                            crest,
                            with: .color(.white.opacity(0.50 + 0.22 * loudness)),
                            style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                    }
                }
            }
        }
        // Dissolve upward into the glass; solid only at the very bottom.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .white.opacity(0.7), location: 0.55),
                    .init(color: .white, location: 1),
                ],
                startPoint: .top, endPoint: .bottom))
    }
}

/// Check mark that draws itself on, with a small spring pop.
private struct AnimatedCheckmark: View {
    @State private var progress: CGFloat = 0
    @State private var popped = false

    var body: some View {
        CheckShape()
            .trim(from: 0, to: progress)
            .stroke(
                .white,
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: 13, height: 13)
            .scaleEffect(popped ? 1 : 0.6)
            .opacity(popped ? 1 : 0)
            .onAppear {
                // Wait out the capsule's shrink (spring response 0.38) so the
                // check never draws against a still-moving boundary.
                withAnimation(.easeOut(duration: 0.28).delay(0.3)) { progress = 1 }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.28)) {
                    popped = true
                }
            }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.55))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.85))
            p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.95, y: rect.minY + rect.height * 0.18))
            return p
        }
    }
}

extension IndicatorView {
    /// mm:ss, or h:mm:ss past an hour.
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Slow breathing on the recording dot — reads as "live" without shouting.
private struct RecordingPulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
