import Foundation
import Observation

/// JSON Pointer, the subset a UI data model needs.
enum Pointer {
    static func segments(_ pointer: String) -> [String] {
        if pointer.isEmpty || pointer == "/" { return [] }
        guard pointer.hasPrefix("/") else { return [] }
        return pointer.dropFirst().components(separatedBy: "/").map {
            $0.replacingOccurrences(of: "~1", with: "/")
                .replacingOccurrences(of: "~0", with: "~")
        }
    }

    static func get(_ root: [String: JSON], _ pointer: String) -> JSON? {
        var current: JSON = .object(root)
        for segment in segments(pointer) {
            switch current {
            case .object(let o):
                guard let next = o[segment] else { return nil }
                current = next
            case .array(let a):
                guard let i = Int(segment), i >= 0, i < a.count else { return nil }
                current = a[i]
            default:
                return nil
            }
        }
        return current
    }

    /// Largest array index a patch may create. Without a cap, one line of model
    /// output can allocate millions of entries.
    static let maxArrayIndex = 10_000

    static func set(_ root: inout [String: JSON], _ pointer: String, _ value: JSON?) {
        let path = segments(pointer)
        guard !path.isEmpty else { return }
        var container = JSON.object(root)
        setIn(&container, path, value)
        if case .object(let o) = container { root = o }
    }

    private static func setIn(_ node: inout JSON, _ path: [String], _ value: JSON?) {
        guard let key = path.first else { return }
        let rest = Array(path.dropFirst())

        if rest.isEmpty {
            switch node {
            case .object(var o):
                if let value { o[key] = value } else { o.removeValue(forKey: key) }
                node = .object(o)
            case .array(var a):
                guard let i = Int(key), i >= 0, i <= maxArrayIndex else { return }
                if let value {
                    while a.count <= i { a.append(.null) }
                    a[i] = value
                } else if i < a.count {
                    a.remove(at: i)
                }
                node = .array(a)
            default:
                break
            }
            return
        }

        let wantsArray = Int(rest[0]) != nil
        switch node {
        case .object(var o):
            var child = o[key] ?? (wantsArray ? .array([]) : .object([:]))
            if child.objectValue == nil && child.arrayValue == nil {
                child = wantsArray ? .array([]) : .object([:])
            }
            setIn(&child, rest, value)
            o[key] = child
            node = .object(o)
        case .array(var a):
            guard let i = Int(key), i >= 0, i <= maxArrayIndex else { return }
            while a.count <= i { a.append(wantsArray ? .array([]) : .object([:])) }
            var child = a[i]
            if child.objectValue == nil && child.arrayValue == nil {
                child = wantsArray ? .array([]) : .object([:])
            }
            setIn(&child, rest, value)
            a[i] = child
            node = .array(a)
        default:
            break
        }
    }
}

/// Applies ops and decides when a surface is safe to paint.
///
/// Two rules do most of the work, and they are the same two the TypeScript
/// enforces:
///
/// **Root gate.** Nothing renders until a `root` op names a component that has
/// actually arrived. Without it a surface flashes a half-built tree on its way
/// to being correct, and people read that flash as a bug rather than as progress.
///
/// **Dangling references are normal.** A parent may list children that have not
/// arrived. Those ids draw a placeholder that is swapped in place when the real
/// component lands, so the layout never jumps.
@MainActor
@Observable
public final class SurfaceStore {
    public private(set) var spec = Spec()
    public private(set) var isReady = false
    public private(set) var pending: Set<ComponentID> = []
    public private(set) var warnings: [String] = []

    /// Where events go when someone uses a control.
    ///
    /// Set by whatever owns the socket. Nil means the panel is a display, which
    /// is a legitimate state: a surface streamed and the agent walked away.
    public var onEvent: ((OutboundEvent) -> Void)?

    /// Bumped on every change so SwiftUI redraws even though `spec` is a value
    /// type nested several levels deep.
    public private(set) var revision = 0

    public init() {}

    public func reset() {
        spec = Spec()
        isReady = false
        pending = []
        warnings = []
        revision += 1
    }

    public func apply(_ ops: [Op]) {
        guard !ops.isEmpty else { return }
        for op in ops { applyOne(op) }
        recomputePending()
        if !isReady, let root = spec.root, spec.elements[root] != nil {
            isReady = true
        }
        revision += 1
    }

    public func warn(_ message: String) {
        // Capped: a stream emitting a warning per line should not grow the array
        // without bound behind a HUD nobody is looking at.
        if warnings.count < 50 { warnings.append(message) }
        revision += 1
    }

    private func applyOne(_ op: Op) {
        switch op {
        case .surface, .close, .presence, .mark, .unmark:
            // Routed by the overlay, which owns which surface is current and
            // what the ring is doing. A store knows about one surface's
            // contents and deliberately nothing about the glass around it.
            return

        case .component(let node):
            guard isValidID(node.id) else {
                warn("Invalid component id \(node.id)")
                return
            }
            // Children set by an earlier `>` survive a later `c`, so a model can
            // emit them in either order.
            let existing = spec.elements[node.id]
            var merged = node
            if merged.children.isEmpty, let existing, !existing.children.isEmpty {
                merged.children = existing.children
            }
            spec.elements[node.id] = merged

        case .children(let id, let children):
            guard isValidID(id) else { return }
            if var parent = spec.elements[id] {
                parent.children = children
                spec.elements[id] = parent
            } else {
                // Parent has not arrived. Hold the edge so it applies on arrival.
                spec.elements[id] = ComponentNode(
                    id: id, type: ComponentNode.pendingType, children: children)
            }

        case .data(let path, let value):
            Pointer.set(&spec.data, path, value)

        case .root(let id):
            guard isValidID(id) else { return }
            spec.root = id

        case .surface, .close:
            // Placement is the overlay's business, not a surface's. A store that
            // could move itself would be a store that can fight the layout.
            break
        }
    }

    private func recomputePending() {
        var next: Set<ComponentID> = []
        for node in spec.elements.values {
            for child in node.children {
                if spec.elements[child] == nil
                    || spec.elements[child]?.type == ComponentNode.pendingType {
                    next.insert(child)
                }
            }
        }
        if let root = spec.root, spec.elements[root] == nil { next.insert(root) }
        pending = next
    }

    /// `__` is reserved for internal sentinels, so a stream cannot collide with
    /// the placeholder used for an unresolved child.
    private func isValidID(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64, !id.hasPrefix("__") else { return false }
        return id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Resolve a component's props against the data model, at render time rather
    /// than parse time, so a data patch updates a value without rebuilding it.
    public func resolved(_ node: ComponentNode) -> [String: JSON] {
        var out: [String: JSON] = [:]
        for (key, value) in node.props {
            switch value {
            case .literal(let json):
                out[key] = json
            case .binding(let binding):
                if let found = Pointer.get(spec.data, binding.pointer) { out[key] = found }
            case .computed(let expression):
                out[key] = .number(compute(expression))
            }
        }
        return out
    }

    /// Write a value back locally, then tell the agent.
    ///
    /// Local first is the whole point. A typed character that waits for a round
    /// trip before appearing feels broken, and the agent may not even be
    /// listening. The panel owns its own data model and the event is a
    /// notification, not a request for permission.
    public func write(_ pointer: String, _ value: JSON) {
        Pointer.set(&spec.data, pointer, value)
        revision += 1
        onEvent?(.value(pointer: pointer, value: value))
    }

    /// Write an edited file back, then say so.
    ///
    /// Bounded deliberately: the only path this can write is one that was
    /// handed to a `File` component and then typed in by the person looking at
    /// it. No path is constructed here and none is resolved against anything.
    /// The event goes out either way, so an agent watching knows the document it
    /// put on screen has changed underneath it.
    public func saveFile(path: String, contents: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            onEvent?(.action(
                name: "file.saved",
                component: "File",
                payload: ["path": .string(path)]))
        } catch {
            warn("Could not save \(url.lastPathComponent)")
        }
    }

    public func fire(_ action: String, from component: ComponentID, payload: [String: JSON] = [:]) {
        onEvent?(.action(name: action, component: component, payload: payload))
    }

    /// The pointer a component's prop is bound to, if any.
    public func binding(_ node: ComponentNode, _ prop: String) -> String? {
        if case .binding(let binding) = node.props[prop] { return binding.pointer }
        return nil
    }

    private func compute(_ expression: Computed) -> Double {
        switch expression {
        case .count(let path, let field, let equals):
            guard let rows = Pointer.get(spec.data, path)?.arrayValue else { return 0 }
            guard let field, let equals else { return Double(rows.count) }
            return Double(rows.filter { $0.objectValue?[field] == equals }.count)

        case .sum(let path, let field):
            guard let rows = Pointer.get(spec.data, path)?.arrayValue else { return 0 }
            return rows.compactMap { $0.objectValue?[field]?.doubleValue }.reduce(0, +)

        case .avg(let path, let field):
            guard let rows = Pointer.get(spec.data, path)?.arrayValue else { return 0 }
            let values = rows.compactMap { $0.objectValue?[field]?.doubleValue }
            guard !values.isEmpty else { return 0 }
            // Rounded to one place: an average rating of 4.333333333 is not what
            // anyone meant.
            return (values.reduce(0, +) / Double(values.count) * 10).rounded() / 10
        }
    }
}
