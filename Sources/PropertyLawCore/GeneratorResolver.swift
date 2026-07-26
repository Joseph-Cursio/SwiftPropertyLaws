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
///
/// A reference type so it can memoize across the whole scan: a type's
/// resolution is path-independent (the visited set only breaks cycles, and a
/// cyclic type is non-derivable from every entry point), so every type is
/// computed at most once. Without the memo, deeply nested universes (e.g.
/// swift-syntax) re-resolve shared subtrees exponentially.
public final class GeneratorResolver {
    private let shapesByName: [String: TypeShape]

    /// Names that appeared on **more than one distinct** `TypeShape` in the
    /// universe. Resolution refuses these — see `init(types:aliases:)`.
    private let ambiguousNames: Set<String>

    /// User-declared typealiases collected from the scanned source, mapping
    /// the alias name to its underlying type spelling (e.g. `UserID` → `Int`).
    private let aliases: [String: String]
    private var memo: [String: DerivationStrategist.ComposedGenerator?] = [:]

    /// Build a resolver over a module's type universe.
    ///
    /// **An ambiguous name resolves to nothing, deliberately.** `TypeShape.name`
    /// is a single unqualified string, so a scanner that records nested types
    /// (`Foo.Kind`, `Bar.Kind`) under their bare names hands this initializer
    /// several distinct shapes all called `Kind`. This used to be
    /// `uniquingKeysWith: { first, _ in first }`: the universe silently kept
    /// whichever arrived first, and a member typed `Kind` on `Foo` could be
    /// generated from `Bar`'s nested enum — a generator for **the wrong type**,
    /// emitted with no diagnostic anywhere.
    ///
    /// The two ways to be wrong here are not symmetric, which is what settles
    /// it. Guess, and you emit a plausible expression built from an unrelated
    /// type: it compiles when the shapes happen to be compatible, and the
    /// property then runs against values it was never about. Refuse, and the
    /// referencing type stays `.todo` — a visible boundary the caller can
    /// close by supplying a qualified name.
    ///
    /// So: a name carried by two or more *distinct* shapes is recorded as
    /// ambiguous and resolves to `nil`. Duplicates of the *same* shape (the
    /// same type reached twice while scanning) are not ambiguity and collapse
    /// as before.
    ///
    /// Callers that scan nested types should record and reference them by
    /// qualified name (`Foo.Kind`). Qualified spellings need no support here —
    /// every emitter interpolates `typeName` verbatim, so `Foo.Kind(…)` and
    /// `Gen.element(of: Foo.Kind.allCases)` already come out right.
    ///
    /// Found by SwiftInferProperties' self-dogfood road test, where **eight**
    /// distinct types named `Kind` collapsed to one — and the survivor was an
    /// unrelated CLI-internal enum.
    public init(types: [TypeShape], aliases: [String: String] = [:]) {
        var byName: [String: TypeShape] = [:]
        var ambiguous: Set<String> = []
        for shape in types {
            if let existing = byName[shape.name] {
                // Same type seen twice is not a conflict; two different types
                // sharing a bare name is.
                if existing != shape { ambiguous.insert(shape.name) }
                continue
            }
            byName[shape.name] = shape
        }
        self.shapesByName = byName
        self.ambiguousNames = ambiguous
        self.aliases = aliases
    }

    /// The bare names this resolver refuses because the universe carried more
    /// than one distinct type under each. Exposed so a scanner can report the
    /// collisions rather than wonder why a type stayed `.todo`.
    public var ambiguousTypeNames: Set<String> { ambiguousNames }

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
        if let cached = memo[name] { return cached }         // already fully resolved
        guard !visiting.contains(name) else { return nil }   // recursive cycle (don't memoize the sentinel)

        // Two or more distinct types share this bare name — see the initializer.
        // Refusing keeps the referencing type at `.todo` instead of generating
        // it from whichever namesake happened to be scanned first.
        if ambiguousNames.contains(name) {
            memo[name] = DerivationStrategist.ComposedGenerator?.none
            return nil
        }

        // A user typealias → derive from its underlying type spelling.
        if let underlying = aliases[name] {
            let result = DerivationStrategist.composedGenerator(forTypeName: underlying) { inner in
                self.resolve(inner, visiting: visiting.union([name]))
            }
            memo[name] = result
            return result
        }
        guard let shape = shapesByName[name] else { return nil }   // external / unknown

        let result = derive(shape, visiting: visiting)
        memo[name] = result
        return result
    }

    private func derive(
        _ shape: TypeShape,
        visiting: Set<String>
    ) -> DerivationStrategist.ComposedGenerator? {
        if shape.hasUserGen {
            return DerivationStrategist.ComposedGenerator(expression: "\(shape.name).gen()")
        }
        let nextVisiting = visiting.union([shape.name])
        let strategy = DerivationStrategist.strategy(for: shape) { inner in
            self.resolve(inner, visiting: nextVisiting)
        }
        if case .todo = strategy { return nil }
        return DerivationStrategist.ComposedGenerator(
            expression: GeneratorExpressionEmitter.expression(typeName: shape.name, strategy: strategy),
            requiredImports: strategy.requiredImports
        )
    }
}
