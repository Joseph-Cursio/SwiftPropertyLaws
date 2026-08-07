/// Generator scaffolding (Phases 2–3 of the generator-scaffolding design, pruned
/// from the tree as superseded — `git show e8f1ac4:docs/GENERATOR_SCAFFOLDING_DESIGN.md`).
/// For a type that can't be *fully* auto-derived, produce a best-effort
/// `gen()` stub — slots we can derive filled in, the rest left as
/// `<#Generator<T>#>` editor placeholders — for the developer to complete.
///
/// The trick: reuse the whole Tier 1–6 strategy machinery, but pass a
/// *hole-filling* resolver. The strategies normally bail (`nil`) the moment a
/// slot doesn't resolve; with the hole-filling resolver an unresolvable type
/// becomes a `.hole` instead, so the strategy builds a complete-shaped result
/// whose holes render as placeholders. No duplicate construction logic.
public enum ScaffoldEmitter {

    /// A scaffold `gen()` stub for `shape`, or `nil` when no scaffold applies:
    /// either the type fully derives (no placeholders needed) or it can't be
    /// scaffolded at all — no known constructor (external/opaque types,
    /// classes/actors, empty types). `resolve` is the same whole-module
    /// resolver the complete path uses; nested types that *do* derive are
    /// inlined, the rest become placeholders.
    public static func stub(
        for shape: TypeShape,
        resolve: DerivationStrategist.CustomTypeResolver = { _ in nil }
    ) -> String? {
        let holeFilling: DerivationStrategist.CustomTypeResolver = { name in
            resolve(name) ?? DerivationStrategist.ComposedGenerator(
                plan: .hole(typeName: name, reason: "no generator could be derived")
            )
        }
        let strategy = DerivationStrategist.strategy(for: shape, resolve: holeFilling)
        // No constructor to lift through → not scaffoldable (manual `gen()`).
        if case .todo = strategy { return nil }
        let body = GeneratorExpressionEmitter.expression(typeName: shape.name, strategy: strategy)
        // No placeholders → the type fully derives; no scaffold needed.
        guard body.contains("<#") else { return nil }
        return stubText(typeName: shape.name, body: body)
    }

    private static func stubText(typeName: String, body: String) -> String {
        """
        extension \(typeName) {
            // Scaffolded — fill the <#...#> placeholder(s) to enable property-based testing.
            static func gen() -> Generator<\(typeName), some SendableSequenceType> {
                \(body)
            }
        }
        """
    }
}
