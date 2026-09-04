import Foundation

/// The wire shape, ported from `src/core/spec.ts`.
///
/// Components live in a flat map keyed by id with a named root, not a nested
/// tree. That is what makes a stream renderable out of order: a child may arrive
/// before its parent and neither case needs special handling. Google's A2UI and
/// Vercel's json-render landed on the same shape independently.

public typealias ComponentID = String

/// A JSON value. Swift has no native one, and pulling a dependency for six cases
/// is not worth it in a process whose whole point is starting instantly.
public enum JSON: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSON])
    case object([String: JSON])

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "yes" : "no"
        case .null: return nil
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        case .bool(let b): return b ? 1 : 0
        default: return nil
        }
    }

    public var arrayValue: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var objectValue: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Display text for a table cell or a label.
    public var display: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "yes" : "no"
        case .null: return ""
        case .array(let a): return a.map(\.display).joined(separator: ", ")
        case .object: return ""
        }
    }
}

/// A prop that reads from the data model rather than carrying a literal.
public struct Binding: Sendable, Equatable {
    public let pointer: String
    public init(pointer: String) { self.pointer = pointer }
}

/// A prop derived from the data. The same three forms the TypeScript supports,
/// and no more: every operator is a small expression language that has to be
/// authored correctly by a model and understood by whoever reads the output.
public enum Computed: Sendable, Equatable {
    case count(path: String, whereField: String?, equals: JSON?)
    case sum(path: String, field: String)
    case avg(path: String, field: String)
}

public enum PropValue: Sendable, Equatable {
    case literal(JSON)
    case binding(Binding)
    case computed(Computed)
}

public struct ComponentNode: Sendable, Equatable {
    public var id: ComponentID
    public var type: String
    public var props: [String: PropValue]
    public var children: [ComponentID]

    public init(
        id: ComponentID, type: String,
        props: [String: PropValue] = [:], children: [ComponentID] = []
    ) {
        self.id = id
        self.type = type
        self.props = props
        self.children = children
    }

    /// Marks an edge held for a parent that has not arrived yet.
    public static let pendingType = "__pending__"
}

public struct Spec: Sendable, Equatable {
    public var root: ComponentID?
    public var elements: [ComponentID: ComponentNode]
    public var data: [String: JSON]

    public init(
        root: ComponentID? = nil,
        elements: [ComponentID: ComponentNode] = [:],
        data: [String: JSON] = [:]
    ) {
        self.root = root
        self.elements = elements
        self.data = data
    }
}

/// The four things a stream can say.
public enum Op: Sendable, Equatable {
    case component(ComponentNode)
    case children(id: ComponentID, children: [ComponentID])
    case data(path: String, value: JSON?)
    case root(id: ComponentID)
}
