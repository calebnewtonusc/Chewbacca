import SwiftUI

/// The dashboard family: charts drawn as light rather than as diagrams.
///
/// A dashboard on glass is a different problem from a dashboard on a page. It is
/// glanced at for under a second, over arbitrary content, at whatever brightness
/// the desktop underneath happens to be. So everything conventional gets cut:
/// no axes, no gridlines, no legends, no tick labels, no chart borders. Those
/// exist so a reader can extract a precise value from a printed figure, and
/// nobody extracts precise values from a heads-up display. They read shape.
///
/// The scifiinterfaces breakdown of the Iron Man HUD defers its own critique to
/// exactly this point, naming "the readability of the complex layering and
/// translucency" as the thing that needs answering. The answer taken here is
/// that the number is always written out in plain type next to the shape. The
/// drawing carries the trend; the text carries the value. Neither is asked to do
/// the other's job, which is how the film's HUD gets into trouble.

/// A trend, drawn as a lit ridge.
///
/// The filled area under the line does most of the work at small sizes, because
/// a one-pixel stroke over a live desktop disappears against anything busy. The
/// dot on the final sample is the whole point of the component: it says which
/// end is now.
struct Sparkline: View {
    let label: String
    let points: [Double]
    let value: String
    let tone: Color

    private var normalized: [Double] {
        guard let low = points.min(), let high = points.max() else { return [] }
        let span = high - low
        // A flat series is a real series. Without this it divides by zero and
        // draws nothing, which reads as missing data rather than as steady.
        guard span > 0 else { return points.map { _ in 0.5 } }
        return points.map { ($0 - low) / span }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.3)
                    .foregroundStyle(HUD.faint)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(HUD.ink)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                let scaled = normalized
                let size = proxy.size
                ZStack(alignment: .topLeading) {
                    if scaled.count > 1 {
                        Area(values: scaled)
                            .fill(LinearGradient(
                                colors: [tone.opacity(0.30), tone.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                        Ridge(values: scaled)
                            .stroke(tone, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                            .shadow(color: tone.opacity(0.7), radius: 3)
                        Circle()
                            .fill(tone)
                            .frame(width: 4, height: 4)
                            .shadow(color: tone, radius: 4)
                            .position(
                                x: size.width,
                                y: size.height * (1 - (scaled.last ?? 0)))
                    }
                }
            }
            .frame(height: 34)
            .animation(.easeOut(duration: 0.45), value: points)
        }
    }
}

/// The line itself.
private struct Ridge: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: CGFloat(index) * step, y: rect.height * (1 - value))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The same line, closed along the bottom so it can be filled.
private struct Area: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let step = rect.width / CGFloat(values.count - 1)
        path.move(to: CGPoint(x: 0, y: rect.height))
        for (index, value) in values.enumerated() {
            path.addLine(to: CGPoint(x: CGFloat(index) * step, y: rect.height * (1 - value)))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Ranked rows. Horizontal, because the labels are words.
///
/// Vertical bars force the category names sideways or into a legend, and both
/// are worse than simply turning the chart on its side. The bar and its label
/// share a line, so the eye never has to match a colour to a key.
struct BarsView: View {
    let caption: String
    let rows: [JSON]
    let tone: Color

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let display: String
    }

    private var parsed: [Row] {
        rows.compactMap { row in
            guard let object = row.objectValue else { return nil }
            let raw = object["value"]?.doubleValue ?? 0
            return Row(
                label: object["label"]?.display ?? "",
                value: raw,
                display: object["display"]?.display ?? object["value"]?.display ?? "")
        }
    }

    var body: some View {
        // Scale against the largest bar, not against zero-to-max of the axis.
        // On four rows within ten percent of each other a zero-based scale draws
        // four identical bars and says nothing.
        let peak = max(parsed.map(\.value).max() ?? 1, 0.0001)
        VStack(alignment: .leading, spacing: 7) {
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.3)
                    .foregroundStyle(HUD.faint)
            }
            ForEach(parsed) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(row.label)
                            .font(.system(size: 11))
                            .foregroundStyle(HUD.ink.opacity(0.88))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(row.display)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(HUD.dim)
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.07))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [tone.opacity(0.55), tone],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * (row.value / peak))
                                .shadow(color: tone.opacity(0.5), radius: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        // On the values, not just the count. Four rows whose numbers all
        // changed is the common case and the first version animated none of it,
        // because the count had stayed the same.
        .animation(
            .spring(response: 0.36, dampingFraction: 0.85),
            value: parsed.map(\.value))
    }
}

/// A proportion, drawn as an arc.
///
/// Reserved for things that genuinely have a ceiling: a battery, a quota, a
/// percentage of a known total. A ring around an unbounded number is decoration,
/// and decoration on a HUD costs the same attention as information while
/// carrying none.
struct RingView: View {
    let label: String
    let fraction: Double
    let caption: String
    let tone: Color

    var body: some View {
        let clamped = min(max(fraction, 0), 1)
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: clamped)
                    .stroke(
                        AngularGradient(
                            colors: [tone.opacity(0.6), tone],
                            center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    // Start at twelve o'clock. SwiftUI trims from three.
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tone.opacity(0.6), radius: 5)
                Text(caption.isEmpty ? "\(Int(clamped * 100))%" : caption)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(HUD.ink)
                    .monospacedDigit()
            }
            .frame(width: 62, height: 62)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(HUD.faint)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: clamped)
    }
}

/// Things that happened, most recent first.
///
/// Named `Events` rather than `Timeline` because SwiftUI already owns
/// `TimelineView` and a shadowed name produces errors that point at the call
/// site instead of the declaration.
struct EventsView: View {
    let caption: String
    let items: [JSON]
    let tone: Color

    private struct Event: Identifiable {
        let id = UUID()
        let time: String
        let text: String
        let accent: Bool
    }

    private var parsed: [Event] {
        items.compactMap { item in
            guard let object = item.objectValue else {
                // A plain string is a legitimate event with no timestamp, and
                // rejecting it would make the simplest possible list fail.
                guard let text = item.stringValue else { return nil }
                return Event(time: "", text: text, accent: false)
            }
            return Event(
                time: object["time"]?.display ?? "",
                text: object["text"]?.display ?? "",
                accent: object["accent"] == .bool(true))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.3)
                    .foregroundStyle(HUD.faint)
                    .padding(.bottom, 7)
            }
            ForEach(Array(parsed.enumerated()), id: \.element.id) { index, event in
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(HUD.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    if !event.time.isEmpty {
                        Text(event.time)
                            .font(.system(size: 9.5))
                            .foregroundStyle(HUD.faint)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 14)
                .padding(.bottom, index == parsed.count - 1 ? 0 : 9)
                // The rail is drawn as a *background* of the text, not as a
                // sibling in an HStack.
                //
                // As a sibling it was the bug that made every event forty points
                // tall: a `Rectangle` is infinitely flexible vertically, so in an
                // HStack it accepted the full height the column was offered and
                // dragged the row with it. A background is sized to its host, so
                // the text decides the height and the rail simply matches.
                .background(alignment: .topLeading) {
                    ZStack(alignment: .top) {
                        Rectangle()
                            .fill(.white.opacity(0.10))
                            .frame(width: 1)
                            // No rail above the first dot or below the last one:
                            // the thread connects events, it does not dangle.
                            .padding(.top, index == 0 ? 5 : 0)
                            .padding(.bottom, index == parsed.count - 1 ? 6 : 0)
                        Circle()
                            .fill(event.accent ? tone : HUD.faint)
                            .frame(width: 5, height: 5)
                            .shadow(color: event.accent ? tone : .clear, radius: 4)
                            .padding(.top, 3)
                    }
                    .frame(width: 5)
                }
            }
        }
    }
}
