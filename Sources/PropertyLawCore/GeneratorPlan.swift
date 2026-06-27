/// Structured representation of a composed generator — the tree the string
/// emitters render. Introduced as Phase 1 of generator scaffolding (see
/// `docs/GENERATOR_SCAFFOLDING_DESIGN.md`): replacing the opaque emitted
/// string with a tree is what later lets a slot be a `.hole` (Phase 2) and
/// lets SwiftInferProperties refine/fill nodes structurally (Phase 4).
///
/// This phase covers only the nodes the composite parser
/// (`composedGenerator`) produces — leaves and collection wrappers. Product
/// (memberwise / init / enum-payload) and sum (`oneOf`) nodes, plus the
/// `.hole` placeholder, arrive with the partial-derivation phases. Output is
/// byte-identical to the previous string emitter (locked by existing tests).
public indirect enum GeneratorPlan: Sendable, Equatable {
    /// A fully-resolved generator expression and the modules it must name —
    /// a recognized raw / known value type, or an inlined / `Type.gen()`
    /// reference produced by the custom-type resolver.
    case leaf(expression: String, imports: Set<String>)
    /// `T?` → `<element>.optional`.
    case optional(GeneratorPlan)
    /// `[T]` → `<element>.array(of: 0...8)`.
    case array(GeneratorPlan)
    /// `Set<T>` → `<element>.set(ofAtMost: 0...8)`.
    case set(GeneratorPlan)
    /// `[K: V]` → `zip(<key>, <value>).dictionary(ofAtMost: 0...8)`.
    case dictionary(key: GeneratorPlan, value: GeneratorPlan)
    /// An unresolvable slot — a type with no derivable generator. Renders as
    /// a Swift editor placeholder for the developer to fill (scaffolding).
    case hole(typeName: String, reason: String)

    /// The `swift-property-based` source expression for this plan. A `.hole`
    /// renders as a `<#Generator<T>#>` editor placeholder.
    public var rendered: String {
        switch self {
        case .leaf(let expression, _):
            return expression
        case .optional(let element):
            return "\(element.rendered).optional"
        case .array(let element):
            return "\(element.rendered).array(of: 0...8)"
        case .set(let element):
            return "\(element.rendered).set(ofAtMost: 0...8)"
        case .dictionary(let key, let value):
            return "zip(\(key.rendered), \(value.rendered)).dictionary(ofAtMost: 0...8)"
        case .hole(let typeName, _):
            return "<#Generator<\(typeName)>#>"
        }
    }

    /// Modules `rendered` must be able to name (unioned over the tree).
    public var requiredImports: Set<String> {
        switch self {
        case .leaf(_, let imports):
            return imports
        case .optional(let element), .array(let element), .set(let element):
            return element.requiredImports
        case .dictionary(let key, let value):
            return key.requiredImports.union(value.requiredImports)
        case .hole:
            return []
        }
    }

    /// `true` when no slot in the tree is a `.hole` — i.e. fully derivable.
    public var isComplete: Bool {
        switch self {
        case .leaf:
            return true
        case .optional(let element), .array(let element), .set(let element):
            return element.isComplete
        case .dictionary(let key, let value):
            return key.isComplete && value.isComplete
        case .hole:
            return false
        }
    }
}
