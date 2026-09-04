import SwiftUI

/// Renders a streamed spec as native SwiftUI.
///
/// This is the piece that does not exist anywhere else. Every generative UI
/// system renders to HTML, because HTML is what a model already knows how to
/// emit and what a browser already knows how to draw. Rendering the same stream
/// as native views means no browser, no WebView, no bundle, and a window that
/// can float over everything and take the system's own typography and materials.
///
/// The rules are the same three the web renderer follows, and they matter more
/// here rather than less, because a HUD is glanced at rather than read:
///
/// - Nothing paints before the root resolves.
/// - A child that has not arrived draws a placeholder in place, so the layout
///   does not jump when it lands.
/// - Bound and computed props resolve at render time, so a data patch updates a
///   number without rebuilding the component around it.
@MainActor
public struct SurfaceView: View {
    private let store: SurfaceStore

    public init(store: SurfaceStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.isReady, let root = store.spec.root {
                node(root, ancestors: [])
            } else {
                ThinkingView()
            }
        }
        .animation(.easeOut(duration: 0.18), value: store.revision)
    }

    /// `ancestors` is the path from the root, not everything already drawn.
    ///
    /// A set of everything drawn makes the render impure and silently breaks a
    /// legitimate DAG, where one component is referenced by two parents. Path
    /// scoping cuts only genuine cycles.
    private func node(_ id: ComponentID, ancestors: Set<ComponentID>) -> AnyView {
        if ancestors.contains(id) { return AnyView(EmptyView()) }
        guard let element = store.spec.elements[id],
              element.type != ComponentNode.pendingType
        else { return AnyView(PlaceholderView()) }
        return AnyView(
            render(element, ancestors: ancestors.union([id]))
                // Identity keyed on the *type*, so a component that becomes a
                // different kind of component transitions instead of snapping.
                //
                // Changing props keeps the identity and animates in place: a
                // number rolls, a bar grows, a diagram's nodes travel. Changing
                // the type cannot animate in place, because there is no sensible
                // halfway point between a table and a chart, so it crossfades
                // and scales instead. Both read as the interface responding
                // rather than being rebuilt, which is the whole difference
                // between this and a slideshow.
                .id(element.type)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.97)),
                    removal: .opacity.combined(with: .scale(scale: 1.02)))))
    }

    @ViewBuilder
    private func children(of element: ComponentNode, ancestors: Set<ComponentID>) -> some View {
        ForEach(element.children, id: \.self) { child in
            node(child, ancestors: ancestors)
        }
    }

    /// Dispatch to a small builder per family.
    ///
    /// This is split rather than written as one switch for a boring but decisive
    /// reason: a single `@ViewBuilder` switch with twelve branches makes Swift
    /// unify twelve different view types into nested `_ConditionalContent`
    /// generics, and the type checker's cost grows exponentially in the number of
    /// branches. As one function this file took over three and a half minutes of
    /// CPU to compile. Split into families that return `AnyView`, it takes
    /// seconds, and the erasure costs nothing a person could perceive in a panel
    /// that redraws a few times a second.
    private func render(_ element: ComponentNode, ancestors: Set<ComponentID>) -> AnyView {
        let p = store.resolved(element)
        switch element.type {
        case "Screen", "Stack":
            return container(element, p, ancestors)
        case "Heading", "Text", "List":
            return prose(element, p)
        case "Metric", "Table", "Status":
            return data(p, type: element.type)
        case "Sparkline", "Bars", "Ring", "Events":
            return chart(p, type: element.type)
        case "File":
            let path = p["path"]?.stringValue ?? ""
            return AnyView(
                FileView(
                    path: path,
                    editable: p["editable"] == .bool(true),
                    page: Int(p["page"]?.doubleValue ?? 1),
                    onSave: { [store] body in
                        store.saveFile(path: path, contents: body)
                    }))

        case "Diagram":
            return AnyView(
                DiagramView(
                    parts: p["parts"]?.arrayValue ?? [],
                    aspect: p["aspect"]?.doubleValue ?? 2,
                    tone: HUD.tone(p["tone"]?.stringValue)))
        default:
            return control(element, p)
        }
    }

    private func container(
        _ element: ComponentNode, _ p: [String: JSON], _ ancestors: Set<ComponentID>
    ) -> AnyView {
        if element.type == "Screen" {
            return AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    Text(p["title"]?.display ?? "")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .kerning(0.4)
                        .foregroundStyle(HUD.ink)
                    children(of: element, ancestors: ancestors)
                })
        }

        let gap = CGFloat(p["gap"]?.doubleValue ?? 2) * 4

        // A grid, because a dashboard is not a column.
        //
        // Every serious dashboard tool lays panels out in a grid and the first
        // version of this could only stack, so four metrics took four times the
        // vertical space they needed and pushed everything else off a panel that
        // is already height-capped. Columns are fixed rather than adaptive: the
        // model asked for two, and a grid that silently reflows to one is a
        // layout the author cannot reason about.
        if p["direction"]?.stringValue == "grid" {
            let columns = max(1, min(Int(p["cols"]?.doubleValue ?? 2), 4))
            return AnyView(
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: gap, alignment: .topLeading),
                        count: columns),
                    alignment: .leading,
                    spacing: gap
                ) {
                    children(of: element, ancestors: ancestors)
                })
        }

        if p["direction"]?.stringValue == "horizontal" {
            return AnyView(
                HStack(alignment: .top, spacing: gap) {
                    children(of: element, ancestors: ancestors)
                })
        }
        return AnyView(
            VStack(alignment: .leading, spacing: gap) {
                children(of: element, ancestors: ancestors)
            })
    }

    private func prose(_ element: ComponentNode, _ p: [String: JSON]) -> AnyView {
        switch element.type {
        case "Heading":
            let level = Int(p["level"]?.doubleValue ?? 2)
            return AnyView(
                Text(p["text"]?.display ?? "")
                    .font(.system(size: level == 1 ? 14 : 11.5, weight: .semibold))
                    .foregroundStyle(HUD.dim)
                    .padding(.top, 2))

        case "Text":
            let muted = p["tone"]?.stringValue == "muted"
            return AnyView(
                Text(p["value"]?.display ?? "")
                    .font(.system(size: 12.5))
                    .foregroundStyle(muted ? HUD.faint : HUD.ink.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true))

        default:
            let items = p["items"]?.arrayValue ?? []
            let ordered = p["ordered"] == .bool(true)
            return AnyView(ListView(items: items, ordered: ordered))
        }
    }

    private func data(_ p: [String: JSON], type: String) -> AnyView {
        switch type {
        case "Metric":
            let value = p["value"]?.display ?? ""
            let tone = Self.threshold(p, value: p["value"]?.doubleValue)
            return AnyView(
                MetricView(
                    label: p["label"]?.display ?? "",
                    value: value,
                    unit: p["unit"]?.stringValue,
                    tone: tone)
                    // Digits roll rather than cutting. A number that changes
                    // under your eye is the one thing on a HUD you always want
                    // to have noticed.
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: value))

        case "Table":
            let columns = (p["columns"]?.arrayValue ?? []).compactMap { column -> Column? in
                guard let object = column.objectValue,
                      let field = object["field"]?.stringValue else { return nil }
                return Column(field: field, label: object["label"]?.stringValue ?? field)
            }
            let rows = p["rows"]?.arrayValue ?? []
            return AnyView(
                TableView(
                    caption: p["caption"]?.display ?? "",
                    columns: columns,
                    rows: rows)
                    .animation(.spring(response: 0.34, dampingFraction: 0.85), value: rows.count))

        default:
            return AnyView(
                StatusView(
                    message: p["message"]?.display ?? "",
                    level: p["level"]?.stringValue ?? "info"))
        }
    }

    /// The dashboard family.
    ///
    /// Kept apart from `data` for the same compile-time reason the other
    /// families are split, and because it is the family with the most branches
    /// still to come.
    ///
    /// Every one of these takes a `tone`, defaulting to the HUD accent. A
    /// dashboard where each panel picks its own colour is unreadable, so the
    /// model has to ask for a different one deliberately and gets the house cyan
    /// when it does not.
    private func chart(_ p: [String: JSON], type: String) -> AnyView {
        let tone = HUD.tone(p["tone"]?.stringValue)
        switch type {
        case "Sparkline":
            let points = (p["points"]?.arrayValue ?? []).compactMap(\.doubleValue)
            return AnyView(
                Sparkline(
                    label: p["label"]?.display ?? "",
                    points: points,
                    value: p["value"]?.display ?? "",
                    tone: tone))

        case "Bars":
            return AnyView(
                BarsView(
                    caption: p["caption"]?.display ?? "",
                    rows: p["rows"]?.arrayValue ?? [],
                    tone: tone))

        case "Ring":
            let fraction = p["value"]?.doubleValue ?? 0
            return AnyView(
                RingView(
                    label: p["label"]?.display ?? "",
                    fraction: fraction,
                    caption: p["caption"]?.display ?? "",
                    tone: Self.threshold(p, value: fraction) ?? tone))

        default:
            return AnyView(
                EventsView(
                    caption: p["caption"]?.display ?? "",
                    items: p["items"]?.arrayValue ?? [],
                    tone: tone))
        }
    }

    /// The tone a value has earned, or nil to leave it alone.
    ///
    /// `thresholds=[{"at":80,"tone":"warn"},{"at":95,"tone":"bad"}]`. The last
    /// crossed one wins, so they may be given in any order.
    ///
    /// This is the one dashboard feature worth taking from the tools that do
    /// nothing else: a number that turns amber on its own is read correctly at a
    /// glance, and a number that is only ever cyan has to be read.
    static func threshold(_ p: [String: JSON], value: Double?) -> Color? {
        guard let value, let rules = p["thresholds"]?.arrayValue else { return nil }
        var crossed: (at: Double, tone: String)?
        for rule in rules {
            guard let fields = rule.objectValue,
                  let at = fields["at"]?.doubleValue,
                  let name = fields["tone"]?.stringValue,
                  value >= at
            else { continue }
            if crossed == nil || at > crossed!.at { crossed = (at, name) }
        }
        return crossed.map { HUD.tone($0.tone) }
    }

    /// Live controls, not pictures of controls.
    ///
    /// The first version drew a button as a capsule of text, on the reasoning
    /// that a HUD is glanced at rather than used. That was wrong: a panel that
    /// cannot answer is a poster. A control writes to the local data model
    /// immediately and sends an event up the socket, so it responds at typing
    /// speed whether or not an agent is still listening.
    private func control(_ element: ComponentNode, _ p: [String: JSON]) -> AnyView {
        switch element.type {
        case "Button":
            let action = p["action"]?.stringValue ?? ""
            var payload: [String: JSON] = [:]
            if let collection = p["collection"] { payload["collection"] = collection }
            let primary = p["variant"]?.stringValue == "primary"
            return AnyView(
                Button {
                    store.fire(action, from: element.id, payload: payload)
                } label: {
                    Text(p["label"]?.display ?? "")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(HUDButtonStyle(primary: primary)))

        case "Checkbox":
            let pointer = store.binding(element, "value")
            return AnyView(
                Toggle(
                    isOn: Binding(
                        get: { p["value"] == .bool(true) },
                        set: { next in
                            guard let pointer else { return }
                            store.write(pointer, .bool(next))
                        })
                ) {
                    Text(p["label"]?.display ?? "").font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .disabled(pointer == nil))

        case "Select":
            let pointer = store.binding(element, "value")
            let options = (p["options"]?.arrayValue ?? []).map(\.display)
            return AnyView(
                LabeledControl(label: p["label"]?.display ?? "") {
                    Picker("", selection: Binding(
                        get: { p["value"]?.display ?? "" },
                        set: { next in
                            guard let pointer else { return }
                            store.write(pointer, .string(next))
                        })
                    ) {
                        Text("—").tag("")
                        ForEach(options, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(pointer == nil)
                })

        case "Field":
            let pointer = store.binding(element, "value")
            let numeric = p["kind"]?.stringValue == "number"
            return AnyView(
                LabeledControl(label: p["label"]?.display ?? "") {
                    TextField(
                        p["placeholder"]?.display ?? "",
                        text: Binding(
                            get: { p["value"]?.display ?? "" },
                            set: { next in
                                guard let pointer else { return }
                                // A number field that stores its text would make
                                // every count downstream wrong, so coerce here.
                                store.write(
                                    pointer,
                                    numeric ? .number(Double(next) ?? 0) : .string(next))
                            })
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .disabled(pointer == nil)
                })

        default:
            // A component the panel does not know draws nothing rather than an
            // error box. A newer catalog should degrade, not shout.
            return AnyView(EmptyView())
        }
    }
}

/// Named so the table's column list is not an inferred tuple array, which is
/// another thing the type checker charges for.
struct Column: Hashable {
    let field: String
    let label: String
}

/// A label above its control, so a narrow panel does not squeeze the input.
struct LabeledControl<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            content
        }
    }
}

struct HUDButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                primary ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: Capsule())
            .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ListView: View {
    let items: [JSON]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 7) {
                    Text(ordered ? "\(index + 1)." : "▸")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HUD.accent.opacity(0.8))
                    Text(item.display)
                        .font(.system(size: 12.5))
                        .foregroundStyle(HUD.ink.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Pieces

struct MetricView: View {
    let label: String
    let value: String
    let unit: String?
    /// Set by a crossed threshold. Nil means the number has not earned a colour
    /// and stays in the house ink, which most numbers should.
    var tone: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    // Monospaced digits so a number changing in place does not
                    // shove everything beside it sideways.
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tone ?? HUD.ink)
                    // The glow follows the tone too, so a number that has gone
                    // red is red in its light as well as its ink.
                    .shadow(color: (tone ?? HUD.accent).opacity(0.5), radius: 9)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(HUD.faint)
                }
            }
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.9)
                .foregroundStyle(HUD.faint)
        }
        .frame(minWidth: 62, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct TableView: View {
    let caption: String
    let columns: [Column]
    let rows: [JSON]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(HUD.dim)
            }

            if rows.isEmpty {
                Text("Nothing yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow {
                        ForEach(columns, id: \.self) { column in
                            Text(column.label.uppercased())
                                .font(.system(size: 8.5, weight: .semibold))
                                .kerning(0.9)
                                .foregroundStyle(HUD.accent.opacity(0.75))
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(columns, id: \.self) { column in
                                Text(row.objectValue?[column.field]?.display ?? "")
                                    .font(.system(size: 12))
                                    .foregroundStyle(HUD.ink.opacity(0.92))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(caption)
    }
}

struct StatusView: View {
    let message: String
    let level: String

    private var tint: Color {
        switch level {
        case "success": return .green
        case "warning": return .orange
        case "error": return .red
        default: return .accentColor
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(message).font(.system(size: 12))
        }
        .accessibilityElement(children: .combine)
    }
}

/// Drawn for a child that has been referenced but has not arrived.
///
/// Shaped like a line of text rather than a grey box, because the placeholder
/// and the thing replacing it need the same measure. A rectangle that becomes
/// text reflows, and the eye reads that reflow as a page reload rather than as
/// the same content continuing to arrive.
struct PlaceholderView: View {
    @State private var shimmer = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.quaternary)
            .frame(height: 11)
            .frame(maxWidth: 150, alignment: .leading)
            .opacity(shimmer ? 0.9 : 0.45)
            .task {
                // Respect the system setting rather than animating regardless.
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Shown between a request arriving and the root resolving.
struct ThinkingView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(0.35 + 0.5 * abs(sin(phase + Double(i) * 0.7)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 10)
        .task {
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                phase += 0.22
            }
        }
        .accessibilityLabel("Building")
    }
}
