/// Tier 3 — resolves nested custom-type generators across a whole-module
/// type universe. Derivation can't see sibling types from a single
/// `TypeShape` in isolation, so the discovery plugin (which scans the whole
/// module) builds a `GeneratorResolver` from every `TypeShape` it found and
/// passes `customTypeGenerator(forTypeName:)` as the `resolve` closure to
/// `DerivationStrategist.strategy(for:resolve:)`.
///
/// When a member or init parameter is a custom type, the resolver:
/// - references `Type.gen()` if the type supplies a user generator;
/// - otherwise recursively derives the type's own strategy and *inlines* its
///   generator expression (so the generated test is self-contained — no
///   generated `gen()` methods required);
/// - returns `nil` for external types (not in the universe) and for
///   recursive cycles (guarded by a visited set), which keep the referencing
///   type at `.todo`.
///
/// The macro path doesn't use this — it only sees one type, so nested custom
/// members stay `.todo` there (the `resolve` default).
public struct GeneratorResolver {
    private let shapesByName: [String: TypeShape]

    public init(types: [TypeShape]) {
        self.shapesByName = Dictionary(
            types.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Resolve closure for `DerivationStrategist.strategy(for:resolve:)` and
    /// `composedGenerator(forTypeName:resolve:)`: maps a bare custom-type
    /// spelling to its generator, recursing through the universe.
    public func customTypeGenerator(
        forTypeName name: String
    ) -> DerivationStrategist.ComposedGenerator? {
        resolve(name, visiting: [])
    }

    private func resolve(
        _ name: String,
        visiting: Set<String>
    ) -> DerivationStrategist.ComposedGenerator? {
        guard !visiting.contains(name) else { return nil }   // recursive cycle
        guard let shape = shapesByName[name] else { return nil }   // external / unknown
        if shape.hasUserGen {
            return DerivationStrategist.ComposedGenerator(expression: "\(name).gen()")
        }
        let nextVisiting = visiting.union([name])
        let strategy = DerivationStrategist.strategy(for: shape) { inner in
            self.resolve(inner, visiting: nextVisiting)
        }
        if case .todo = strategy { return nil }
        return DerivationStrategist.ComposedGenerator(
            expression: GeneratorExpressionEmitter.expression(typeName: name, strategy: strategy),
            requiredImports: strategy.requiredImports
        )
    }
}
