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
        return render(element, ancestors: ancestors.union([id]))
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
        default:
            return control(p, type: element.type)
        }
    }

    private func container(
        _ element: ComponentNode, _ p: [String: JSON], _ ancestors: Set<ComponentID>
    ) -> AnyView {
        if element.type == "Screen" {
            return AnyView(
                VStack(alignment: .leading, spacing: 14) {
                    Text(p["title"]?.display ?? "")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    children(of: element, ancestors: ancestors)
                })
        }

        let gap = CGFloat(p["gap"]?.doubleValue ?? 2) * 4
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
                    .font(.system(size: level == 1 ? 16 : 13, weight: .semibold))
                    .padding(.top, 2))

        case "Text":
            let muted = p["tone"]?.stringValue == "muted"
            return AnyView(
                Text(p["value"]?.display ?? "")
                    .font(.system(size: 12.5))
                    .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
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
            return AnyView(
                MetricView(
                    label: p["label"]?.display ?? "",
                    value: p["value"]?.display ?? "",
                    unit: p["unit"]?.stringValue))

        case "Table":
            let columns = (p["columns"]?.arrayValue ?? []).compactMap { column -> Column? in
                guard let object = column.objectValue,
                      let field = object["field"]?.stringValue else { return nil }
                return Column(field: field, label: object["label"]?.stringValue ?? field)
            }
            return AnyView(
                TableView(
                    caption: p["caption"]?.display ?? "",
                    columns: columns,
                    rows: p["rows"]?.arrayValue ?? []))

        default:
            return AnyView(
                StatusView(
                    message: p["message"]?.display ?? "",
                    level: p["level"]?.stringValue ?? "info"))
        }
    }

    private func control(_ p: [String: JSON], type: String) -> AnyView {
        switch type {
        case "Button":
            // A HUD is a display surface, so a button shows its label and shape
            // without pretending to be wired to anything. Claiming an action it
            // cannot perform would be worse than showing none.
            return AnyView(
                Text(p["label"]?.display ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.secondary))

        case "Field", "Select", "Checkbox":
            return AnyView(
                HStack(spacing: 6) {
                    Text(p["label"]?.display ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(p["value"]?.display ?? "—")
                        .font(.system(size: 12, weight: .medium))
                })

        default:
            // A component the HUD does not know draws nothing rather than an
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

struct ListView: View {
    let items: [JSON]
    let ordered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 7) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(item.display)
                        .font(.system(size: 12.5))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 64, alignment: .leading)
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
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
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(columns, id: \.self) { column in
                                Text(row.objectValue?[column.field]?.display ?? "")
                                    .font(.system(size: 12))
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
