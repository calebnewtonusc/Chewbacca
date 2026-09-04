import SwiftUI

/// Free-form drawing, without free-form code.
///
/// Everything else in the vocabulary is a named component with named props,
/// which is what makes a generated interface auditable: the catalog is finite,
/// so it can be checked once instead of forever. The cost is that a model can
/// only produce arrangements somebody anticipated, and a diagram is exactly the
/// case nobody can anticipate. There is no component for "the shape of this
/// particular idea".
///
/// The usual escape hatch is to let the model emit markup and run it in a
/// sandbox, which costs several times the tokens, cannot be audited at all, and
/// opens a prompt-injection surface. This is the other way out: keep the escape
/// hatch but move it down a layer, from *code* to *geometry*. The model gets
/// points, lines, arrows, boxes and labels in a unit square and can draw
/// anything it wants out of them. Nothing here can execute, fetch, or escape,
/// because none of it is a program. It is a list of shapes.
///
/// Paired with `chrome=bare` this is the thing a heads-up display has always
/// been for and a window manager has never been able to do: a figure that
/// appears over the work with no panel around it, sized to itself. And because
/// the coordinates animate, sending a second diagram does not replace the
/// first, it *moves* it.
struct DiagramView: View {
    let parts: [JSON]
    /// Width divided by height. The caller gives width; this decides the rest,
    /// so a diagram keeps its proportions at any surface size.
    let aspect: Double
    let tone: Color

    /// A ceiling on how much a single diagram may draw.
    ///
    /// Not a security boundary, since nothing here executes. It is a defence
    /// against a model that starts repeating itself and hands over forty
    /// thousand line segments, which would stall the render loop on a panel
    /// that is supposed to be glanceable.
    private static let limit = 400

    var body: some View {
        let shapes = parts.prefix(Self.limit).compactMap(Primitive.init)
        // Kinds and labels ride along as a plain array; only the numbers go
        // through `animatableData`. Interpolating a string is meaningless, and
        // interpolating a *kind* would draw half a circle turning into half a
        // box, which is worse than a straight swap.
        DiagramCanvas(
            channels: AnimatableVector(shapes.flatMap(\.channels)),
            shapes: shapes,
            tone: tone)
            .aspectRatio(aspect > 0 ? aspect : 2, contentMode: .fit)
            .frame(maxWidth: .infinity)
            // Fast enough to feel like a response, slow enough to be followed.
            // The first pass ran at 0.75 and read as sluggish: on a HUD you are
            // glancing at, an animation you have time to watch is one you had to
            // wait for.
            .animation(
                .spring(response: 0.34, dampingFraction: 0.82),
                value: AnimatableVector(parts.prefix(Self.limit)
                    .compactMap(Primitive.init).flatMap(\.channels)))
    }
}

/// One drawable thing, split into the part that can be interpolated and the
/// part that cannot.
struct Primitive {
    enum Kind: String {
        case line, arrow, circle, dot, box, node, label
    }

    /// How many numbers each primitive contributes to the animatable vector.
    /// Fixed width per shape, so slicing the vector back apart is arithmetic
    /// rather than bookkeeping.
    static let width = 9

    let kind: Kind
    let label: String
    let toneName: String?
    let dashed: Bool
    let filled: Bool
    /// x, y, x2, y2, r, w, h, stroke, size
    let channels: [Double]

    init?(_ json: JSON) {
        guard let fields = json.objectValue,
              let name = fields["t"]?.stringValue,
              let kind = Kind(rawValue: name)
        else { return nil }
        self.kind = kind
        self.label = fields["label"]?.stringValue ?? fields["text"]?.display ?? ""
        self.toneName = fields["tone"]?.stringValue
        self.dashed = fields["dashed"] == .bool(true)
        self.filled = fields["fill"] == .bool(true)
        self.channels = [
            fields["x"]?.doubleValue ?? 0,
            fields["y"]?.doubleValue ?? 0,
            fields["x2"]?.doubleValue ?? 0,
            fields["y2"]?.doubleValue ?? 0,
            fields["r"]?.doubleValue ?? (kind == .dot ? 0.008 : 0.05),
            fields["w"]?.doubleValue ?? 0.2,
            fields["h"]?.doubleValue ?? 0.16,
            fields["stroke"]?.doubleValue ?? 1.4,
            fields["size"]?.doubleValue ?? 10.5,
        ]
    }
}

/// The canvas that morphs.
///
/// A `View` may conform to `Animatable`, which is the whole trick here: SwiftUI
/// interpolates `animatableData` frame by frame and re-runs `body` with each
/// intermediate value, so a `Canvas` that reads its coordinates out of that
/// vector redraws along the path between two diagrams instead of cutting
/// between them.
/// `nonisolated` because `Animatable` is not main-actor bound and Swift 6 will
/// not let a main-actor conformance satisfy it. Nothing in here touches shared
/// state: it reads a vector of doubles and draws.
nonisolated struct DiagramCanvas: View, Animatable {
    var channels: AnimatableVector
    let shapes: [Primitive]
    let tone: Color

    var animatableData: AnimatableVector {
        get { channels }
        set { channels = newValue }
    }

    var body: some View {
        // Edges in a Canvas, nodes as real views.
        //
        // Everything used to be drawn in the Canvas, and the nodes came out as
        // flat black rectangles with a cyan outline: next to a card made of
        // frosted material they looked like holes punched in the screen. A
        // Canvas cannot sample what is behind the window, so a node painted
        // inside one can never be glass, however it is filled. Lifting them out
        // costs one view per node and makes them the same material as
        // everything else on the display.
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                edges(in: proxy.size)
                ForEach(Array(shapes.enumerated()), id: \.offset) { index, shape in
                    if shape.kind == .node || shape.kind == .box {
                        chip(shape, index: index, in: proxy.size)
                    }
                }
            }
        }
    }

    /// Lines, arrows, circles, dots and free labels.
    private func edges(in size: CGSize) -> some View {
        Canvas { context, _ in
            // Bloom, drawn as a blurred pass beneath a crisp one.
            //
            // This is what separates a lit interface from a technical drawing,
            // and it has to be done here rather than with a `.shadow` on the
            // view, because a shadow on a Canvas blurs the composite: strokes
            // and text and fills all smear together into the grey cloud that
            // made the first version look dirty. Inside the canvas the glow can
            // be strokes only, and the fills stay hard-edged.
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: 7))
                layer.opacity = 0.75
                paint(&layer, size: size, glowing: true)
            }
            paint(&context, size: size, glowing: false)
        }
    }

    /// One node, as glass.
    private func chip(_ shape: Primitive, index: Int, in size: CGSize) -> some View {
        let start = index * Primitive.width
        let values = start + Primitive.width <= channels.values.count
            ? Array(channels.values[start..<(start + Primitive.width)])
            : shape.channels
        let colour = shape.toneName == nil ? tone : HUD.tone(shape.toneName)
        let boxWidth = values[5] * size.width
        let boxHeight = values[6] * size.height

        return Text(shape.label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(HUD.ink)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
            .frame(width: boxWidth, height: boxHeight)
            // `.ultraThinMaterial` rather than the AppKit view the card uses:
            // it is a plain SwiftUI shape style, so it works inside a
            // nonisolated view, and the surface already forces a dark scheme
            // around it so it frosts dark instead of white.
            .background(.ultraThinMaterial, in: shell)
            .background(Color.black.opacity(0.34), in: shell)
            .overlay {
                // The same sheen the cards have, scaled down. A node is a small
                // pane of the same material and should catch the light the same
                // way, or the diagram looks like it came from another program.
                shell.fill(
                    RadialGradient(
                        colors: [.white.opacity(0.18), .clear],
                        center: UnitPoint(x: 0.15, y: -0.1),
                        startRadius: 0, endRadius: 90))
            }
            .overlay {
                // Lit from above, like the card. A uniform outline on all four
                // sides is what made these read as diagram boxes rather than as
                // objects with a light on them.
                shell.strokeBorder(
                    LinearGradient(
                        colors: [
                            colour.opacity(0.85),
                            colour.opacity(0.30),
                            .white.opacity(0.06),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.9)
            }
            .shadow(color: colour.opacity(0.28), radius: 9)
            .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
            .position(x: values[0] * size.width, y: values[1] * size.height)
    }

    private var shell: RoundedRectangle {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
    }

    /// Draw every shape once.
    private func paint(_ context: inout GraphicsContext, size: CGSize, glowing: Bool) {
        for (index, shape) in shapes.enumerated() {
            let start = index * Primitive.width
            guard start + Primitive.width <= channels.values.count else { continue }
            draw(
                shape,
                values: Array(channels.values[start..<(start + Primitive.width)]),
                in: &context, size: size, glowing: glowing)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func draw(
        _ shape: Primitive, values: [Double],
        in context: inout GraphicsContext, size: CGSize, glowing: Bool
    ) {
        let colour = shape.toneName == nil ? tone : HUD.tone(shape.toneName)
        let stroke = values[7]

        // Unit square in, points out. The model never sees a pixel, which is
        // the same reason surfaces are placed by region rather than coordinate:
        // it does not know the size of anything and should not have to.
        let from = CGPoint(x: values[0] * size.width, y: values[1] * size.height)
        let to = CGPoint(x: values[2] * size.width, y: values[3] * size.height)

        switch shape.kind {
        case .line, .arrow:
            var path = Path()
            path.move(to: from)
            path.addLine(to: to)
            if shape.dashed {
                context.stroke(
                    path, with: .color(colour.opacity(0.8)),
                    style: StrokeStyle(lineWidth: stroke, dash: [4, 4]))
            } else {
                context.stroke(path, with: .color(colour), lineWidth: stroke)
            }
            if shape.kind == .arrow {
                context.stroke(head(from: from, to: to), with: .color(colour), lineWidth: stroke)
            }

        case .circle:
            // Radius scales off the width alone, so a circle stays a circle
            // rather than becoming an ellipse when the aspect ratio changes.
            let radius = values[4] * size.width
            let path = Path(ellipseIn: CGRect(
                x: from.x - radius, y: from.y - radius,
                width: radius * 2, height: radius * 2))
            if shape.filled && !glowing {
                context.fill(path, with: .color(colour.opacity(0.18)))
            }
            context.stroke(path, with: .color(colour), lineWidth: stroke)

        case .dot:
            let radius = values[4] * size.width
            context.fill(
                Path(ellipseIn: CGRect(
                    x: from.x - radius, y: from.y - radius,
                    width: radius * 2, height: radius * 2)),
                with: .color(colour))

        case .box, .node:
            // Drawn as a view in `chip`, because a Canvas cannot be glass.
            return

        case .label:
            // Glow behind a word is a smudge, so text is drawn once, crisp.
            guard !glowing else { return }
            text(
                shape.label, at: from, size: values[8],
                colour: shape.toneName == nil ? HUD.ink.opacity(0.9) : colour,
                in: &context, backed: true)
        }
    }

    /// The two short strokes at the end of an arrow.
    private func head(from: CGPoint, to: CGPoint) -> Path {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let length: CGFloat = 7
        let spread: CGFloat = .pi / 7
        var path = Path()
        for side in [angle - spread, angle + spread] {
            path.move(to: to)
            path.addLine(to: CGPoint(
                x: to.x - length * cos(side),
                y: to.y - length * sin(side)))
        }
        return path
    }

    /// Centred text, optionally on its own plate.
    private func text(
        _ string: String, at point: CGPoint, size: Double,
        colour: Color, in context: inout GraphicsContext, backed: Bool
    ) {
        let resolved = context.resolve(
            Text(string)
                .font(.system(size: size, weight: .medium, design: .rounded))
                .foregroundStyle(colour))
        if backed {
            // `resolve` can measure, which is the only way to fit a plate to a
            // string. A blurred shadow was the alternative and it is what made
            // the first version look smudged: a soft grey cloud around every
            // word, with the page still readable through it.
            let bounds = resolved.measure(in: CGSize(width: 400, height: 100))
            let plate = CGRect(
                x: point.x - bounds.width / 2 - 5,
                y: point.y - bounds.height / 2 - 2,
                width: bounds.width + 10,
                height: bounds.height + 4)
            context.fill(
                Path(roundedRect: plate, cornerRadius: 4, style: .continuous),
                with: .color(.black.opacity(0.82)))
        }
        context.draw(resolved, at: point, anchor: .center)
    }
}
