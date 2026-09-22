import SwiftUI

/// The pill: one line at the bottom of the screen that is the whole
/// conversation from the person's side.
///
/// It shows the words as they are said, the agent's breadcrumbs while it
/// works, and the answer when it is done. While a run is in flight the pill's
/// own body fills left to right, the way Safari's address bar does, so the one
/// object on screen is also the loading bar. It replaces the two cards at the
/// top of the screen that popped in to say "nobody is listening" and "still
/// working", which were the size of a dialog and read as one.
public struct PillState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable, CaseIterable {
        case hidden, hearing, heard, working, saying, failed
    }

    public var phase: Phase = .hidden
    /// What the person said. Live partials while the key is held, final after.
    public var heard = ""
    /// The agent's current line: a breadcrumb while working, the answer after.
    public var saying = ""
    /// When the run in flight began. Set once when work starts and cleared
    /// only when it ends, so a press of the key in the middle of a run does
    /// not send the bar and the counter back to zero.
    public var startedAt: Date?
    /// Requests waiting behind the one in flight.
    public var queued = 0
    /// Whether `saying` is a tool step rather than a line of the answer.
    /// The panel shows a step under the answer being written; an answer
    /// line is already in the text.
    public var step = false

    /// What a failure says when the bridge said nothing. Named so an answer
    /// closed with it can still take the real message when one follows.
    public static let unfinished = "Did not finish"

    public init(
        phase: Phase = .hidden, heard: String = "", saying: String = "",
        startedAt: Date? = nil, queued: Int = 0
    ) {
        self.phase = phase
        self.heard = heard
        self.saying = saying
        self.startedAt = startedAt
        self.queued = queued
    }
}

/// p50 and p90 of past runs, measured here rather than sent by the bridge,
/// because the HUD is the one process that sees every run start and end.
public struct RunClock: Sendable {
    /// Seeds are the 60 to 85 seconds measured for the three-errand request in
    /// the research brief. Replaced once enough real runs exist.
    public static let seedP50: TimeInterval = 70
    public static let seedP90: TimeInterval = 85
    /// Twenty. The first measured round trip before --strict-mcp-config was
    /// 190s; a window this size lets one such outlier set p90 for twenty
    /// runs, which is the price of having a p90 at all, and it ages out in a
    /// week of use.
    public static let window = 20
    /// Three. Guessed, never measured: two is not a distribution.
    public static let minimumSamples = 3
    public static let defaultsKey = "hud.runSeconds"

    public var samples: [TimeInterval]

    public init(samples: [TimeInterval]) {
        self.samples = Array(samples.suffix(Self.window))
    }

    public static func load(from defaults: UserDefaults = .standard) -> RunClock {
        RunClock(samples: (defaults.array(forKey: defaultsKey) as? [Double]) ?? [])
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(samples, forKey: Self.defaultsKey)
    }

    public mutating func record(_ seconds: TimeInterval) {
        guard seconds.isFinite, seconds > 0 else { return }
        samples.append(seconds)
        if samples.count > Self.window {
            samples.removeFirst(samples.count - Self.window)
        }
    }

    private var sorted: [TimeInterval] { samples.sorted() }

    public var p50: TimeInterval {
        samples.count >= Self.minimumSamples ? sorted[samples.count / 2] : Self.seedP50
    }

    public var p90: TimeInterval {
        samples.count >= Self.minimumSamples
            ? sorted[Int(0.9 * Double(samples.count - 1))]
            : Self.seedP90
    }
}

/// The capsule at the bottom of the glass.
///
/// Clear glass, in the Apple sense: the screen itself through a capsule that
/// adds a highlight, a rim and a shadow, and nothing that hides what is
/// behind it. It was white for a day, then the cards' dark frost for an
/// hour, and on 2026-09-19 the ask became "bubble/glass apple style pill,
/// fully translucent, clear and white text". macOS 15 has no lens to
/// borrow: NSVisualEffectView blurs at one radius under a tint and reads as
/// frost, so the glass here is a faint white tint, light entering from the
/// top left, a darker underside and a rim. The white ink carries its own
/// shadow, which is what keeps it readable over a white document; the
/// snapshot test draws it over both grounds for that reason.
struct PillView: View {
    let state: PillState
    let presence: Presence
    let amplitude: Double
    let clock: RunClock
    let onCancel: () -> Void
    /// A click anywhere on the capsule but its X: the pill grows into the
    /// conversation panel. The pill itself stays this size; what does not
    /// fit two lines is read there.
    var onExpand: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    private var backdrop: BackdropSampler { .shared }
    /// Whether what is behind the pill is light enough that white ink would
    /// be white on white. Measured, so it is false until a sample exists.
    private var darkInk: Bool {
        (backdrop.luminance ?? 0) > BackdropSampler.lightGround
    }
    /// Whether the completion sweep has faded. Flipped by the phase task, so
    /// the bar finishes in colour and then gets out from under the answer.
    @State private var sweepFaded = false

    /// Distance above the Dock inset. The same 14 the ring already uses, and
    /// `OverlayModel.pillFrame` reads it from here so the hit rectangle and
    /// the drawn one cannot drift apart.
    static let pillLift: CGFloat = 14
    /// 440 fits about 70 characters of 13pt rounded, and the longest demo
    /// answer ("Texted Sagar, put Friday 3pm on the calendar, and Ava is who
    /// to call") is 66. The card it replaces was 460 with a title row.
    static let maxWidth: CGFloat = 440
    /// Never full before the run is. A bar that reaches its end and sits there
    /// is the one every person has learned to distrust. 0.94 leaves about 26pt
    /// empty on a 440pt pill. Guessed, never measured.
    static let progressCap = 0.94
    /// Guessed, never measured: what the fill sweeps at while the run is on,
    /// and what it sits at once it is over and the answer is up. 0.30 on the
    /// white pill, 0.36 on the frosted one; back to 0.30 on clear glass,
    /// where there is no wash for the colour to sit on.
    static let fillOpacity = 0.30
    /// How long the finished bar holds in colour before it fades, and how long
    /// the fade takes. Both guessed, never measured.
    static let sweepHold: Duration = .milliseconds(250)
    static let sweepFade = 0.4

    /// A stable anchor for the tick schedule while nothing is running. The
    /// schedule has to be the same type in every phase or the pill re-enters
    /// on every phase change, so the idle phases keep a periodic schedule too,
    /// one that fires about never.
    private static let idleAnchor = Date()
    /// Guessed, never measured: an hour between idle ticks is one redraw per
    /// hour of a view that is on screen for seconds.
    private static let idlePeriod: TimeInterval = 3600

    var body: some View {
        if state.phase != .hidden {
            TimelineView(.periodic(
                from: state.startedAt ?? Self.idleAnchor,
                by: state.phase == .working ? 1 : Self.idlePeriod)
            ) { context in
                pill(at: context.date)
            }
        }
    }

    private func pill(at now: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(state.startedAt ?? now))
        let progress = progress(elapsed: elapsed)
        // Spacing 8, padding 12 by 7: guessed, never measured. They give the
        // 30pt one-line height the brief asked for at 13pt type.
        return HStack(spacing: 8) {
            PresenceRing(presence: presence, amplitude: amplitude)

            // 13 is macOS body size, rounded because the marker capsule already
            // is. A new line rises in like a caption; 0.18 is the content
            // duration SurfaceView already uses.
            Text(line)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ink)
                // White on clear glass is white on whatever is behind it. The
                // shadow is the legibility: 0.45 at two points is the least
                // that still reads over a white page. Guessed, never measured.
                // Over a measured light ground the ink is dark instead and
                // the shadow turns to a faint lift of white.
                .shadow(color: darkInk ? .white.opacity(0.4) : .black.opacity(0.45), radius: 2, y: 1)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .id(line)
                .transition(.opacity.combined(with: .offset(y: 6)))

            if state.phase == .working {
                counter(elapsed: elapsed)
            }

            if state.queued > 0 {
                Text("+\(state.queued)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(ink.opacity(0.18)))
                    .accessibilityLabel("\(state.queued) waiting")
            }

            CloseButton(action: onCancel, help: helpText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // The loading bar is the pill's own body filling, not a rule under
        // the text: a 2pt line inside a 30pt capsule is invisible from a
        // phone, and the capsule filling is what Safari does, so nobody has
        // to learn it.
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Capsule()
                    .fill(fillTint.opacity(sweepFaded ? 0 : Self.fillOpacity))
                    .frame(width: proxy.size.width * progress)
                    .animation(
                        state.phase == .working
                            ? .linear(duration: 1)
                            : Motion.fade(0.25, reduced: reduceMotion),
                        value: progress)
            }
        }
        // No frost and no wash: the screen through the glass. A tint of
        // white so the capsule exists over black, and an underside that
        // darkens where a lens thickens; the slab adds the bevel, gloss,
        // light and shadows every surface shares. 0.10 and 0.14 are guessed
        // against the eye on 2026-09-19, never measured.
        .modifier(GlassSlab(shape: shape, glow: presence.tint, tilt: 5, clear: true) {
            ZStack {
                // The screen behind, bent through the capsule, once Screen
                // Recording allows it. Drawn past the edge by the bleed so
                // the lens pulls in from outside, and clipped by the slab.
                if let lens = backdrop.lens {
                    Image(decorative: lens, scale: 1)
                        .resizable()
                        .padding(-BackdropSampler.bleed)
                }
                // A touch brighter under the pointer: the one hint that the
                // capsule opens. 0.16 against 0.10, guessed, never measured.
                Color.white.opacity(hovering ? 0.16 : 0.10)
                LinearGradient(
                    colors: [.clear, .black.opacity(0.14)],
                    startPoint: .center, endPoint: .bottom)
            }
        })
        // The whole capsule is the button. The X inside it is a Button of
        // its own and wins the click, so this only fires on the glass.
        .contentShape(shape)
        .onTapGesture { onExpand() }
        .onHover { over in
            hovering = over
            if over { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(Motion.fade(0.14, reduced: reduceMotion), value: hovering)
        .animation(Motion.fade(0.18, reduced: reduceMotion), value: line)
        .environment(\.colorScheme, darkInk ? .light : .dark)
        .animation(Motion.fade(0.3, reduced: reduceMotion), value: darkInk)
        .task(id: state.phase) {
            sweepFaded = false
            guard state.phase == .saying || state.phase == .failed else { return }
            try? await Task.sleep(for: Self.sweepHold)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.fade(Self.sweepFade, reduced: reduceMotion)) {
                sweepFaded = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Open the conversation") { onExpand() }
    }

    /// The elapsed counter. This is the guarantee that something visible
    /// changes every second during a long wait, even when the agent goes
    /// quiet between tool calls.
    private func counter(elapsed: TimeInterval) -> some View {
        let late = elapsed > clock.p90
        return Text(Duration.seconds(Int(elapsed)), format: .time(pattern: .minuteSecond))
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            // White digits on the glass; near-black ones on the amber plate,
            // because white on HUD.warn is 1.5:1 and a phone camera cannot
            // read it.
            .foregroundStyle(late ? .black.opacity(0.85) : ink.opacity(0.78))
            .shadow(color: darkInk ? .white.opacity(late ? 0 : 0.4) : .black.opacity(late ? 0 : 0.45), radius: 2, y: 1)
            .padding(.horizontal, late ? 5 : 0)
            .padding(.vertical, late ? 1 : 0)
            // Past p90 the counter sits on amber rather than turning amber:
            // the same signal at a contrast a phone camera can see.
            .background(HUD.warn.opacity(late ? 0.85 : 0), in: Capsule())
            .accessibilityLabel("\(Int(elapsed)) seconds")
    }

    private var shape: RoundedRectangle {
        // Above half the height SwiftUI clamps the radius, so this is a capsule
        // at one line and still a capsule at two.
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private func progress(elapsed: TimeInterval) -> Double {
        switch state.phase {
        case .working:
            return min(elapsed / max(clock.p90, 1), Self.progressCap)
        case .saying, .failed:
            return 1
        case .hidden, .hearing, .heard:
            return 0
        }
    }

    private var fillTint: Color {
        switch state.phase {
        case .failed: return HUD.bad
        case .saying: return HUD.good
        case .working: return presence == .acting ? HUD.good : HUD.accent
        default: return .clear
        }
    }

    private var isTranscript: Bool {
        state.phase == .hearing || state.phase == .heard
    }

    private var line: String {
        switch state.phase {
        case .hidden: return ""
        case .hearing: return state.heard.isEmpty ? "Listening" : quoted(state.heard)
        case .heard: return quoted(state.heard)
        case .working: return state.saying.isEmpty ? "Working on it" : state.saying
        case .saying, .failed: return state.saying
        }
    }

    private func quoted(_ text: String) -> String {
        "\u{201C}\(text)\u{201D}"
    }

    private var ink: Color {
        let base: Color = darkInk ? .black.opacity(0.86) : HUD.ink
        return isTranscript ? base.opacity(0.78) : base
    }

    private var helpText: String {
        switch state.phase {
        case .hearing, .heard: return "Discard"
        case .working: return "Stop"
        default: return "Dismiss"
        }
    }

    private var accessibilityText: String {
        switch state.phase {
        case .hidden: return ""
        case .hearing: return state.heard.isEmpty ? "Listening" : "Hearing \(state.heard)"
        case .heard: return "Heard \(state.heard)"
        case .working: return "Working. \(line)"
        case .saying: return line
        case .failed: return "Failed. \(line)"
        }
    }
}
