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

    /// Qualified shapes indexed by their last path component, so an
    /// unqualified member reference (`let x: Counted`) can reach
    /// `BitSet.Counted`. Excludes leaves that collide with each other or with a
    /// top-level type of the same name.
    private let shapesByLeafName: [String: TypeShape]

    /// Leaf names carried by two or more distinct qualified shapes.
    private let ambiguousLeafNames: Set<String>

    /// User-declared typealiases collected from the scanned source, mapping
    /// the alias name to its underlying type spelling (e.g. `UserID` → `Int`).
    private let aliases: [String: String]
    private var memo: [String: DerivationStrategist.ComposedGenerator?] = [:]

    /// Helper `func`s built during resolution, keyed by type name.
    ///
    /// Recursive generators cannot be inlined, and the plan tree that carries
    /// their declaration does **not** survive the strategy layer —
    /// `MemberSpec.generatorExpression` is a `String`, so a nested recursive
    /// type's declaration is flattened away the moment it becomes a member.
    /// Accumulating here instead means the caller can ask the resolver what it
    /// built, whatever depth it was built at.
    private var recursiveDeclarations: [String: String] = [:]

    /// Every recursive helper this resolver emitted, sorted for stable output.
    /// Empty unless the universe contained a self-referential type. A caller
    /// writing a stub must emit these **above** the check that calls them.
    public var supportingDeclarations: [String] {
        recursiveDeclarations.keys.sorted().compactMap { recursiveDeclarations[$0] }
    }

    /// Whether `typeName` resolved to a depth-budgeted recursive helper, so a
    /// caller can use the helper call directly as that type's generator rather
    /// than re-composing it memberwise.
    public func isRecursive(_ typeName: String) -> Bool {
        recursiveDeclarations[typeName] != nil
    }

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
        // Leaf index, for the other half of the qualified-name bargain. Once a
        // scanner records `BitSet.Counted`, a member written `let x: Counted`
        // inside `BitSet` stops matching any key — Swift resolves that name
        // through lexical scope, which a flat universe does not model. Without
        // this index, qualifying names would *cost* derivations it was meant to
        // gain.
        //
        // The ambiguity rule is the same one, applied to leaves: a leaf carried
        // by two or more distinct shapes resolves to nothing rather than to
        // whichever was scanned first. That is the `Kind` collision the header
        // above describes, and qualifying the keys does not make guessing safe
        // — it only makes the guess look better informed.
        var byLeaf: [String: TypeShape] = [:]
        var ambiguousLeaves: Set<String> = []
        for shape in types {
            guard let leaf = shape.name.split(separator: ".").last.map(String.init),
                  leaf != shape.name else { continue }
            if let existing = byLeaf[leaf] {
                if existing != shape { ambiguousLeaves.insert(leaf) }
                continue
            }
            byLeaf[leaf] = shape
        }
        // A top-level type always wins its own leaf — `struct Counted` and
        // `Foo.Counted` in one module is not a collision to arbitrate, because
        // an unqualified `Counted` in source means the top-level one everywhere
        // except inside `Foo`. **That fall-out is guaranteed by lookup order,
        // not by pruning the index**: `resolve` consults `shapesByName` first
        // and only reaches the leaf map on a miss, so a leaf that shadows a
        // top-level name is unreachable. An earlier version deleted those
        // entries here; a mutant that removed the deletion changed nothing,
        // which is how the line was found to be dead.
        self.shapesByName = byName
        self.ambiguousNames = ambiguous
        self.shapesByLeafName = byLeaf
        self.ambiguousLeafNames = ambiguousLeaves
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

        // A recursive cycle. This used to `return nil`, pinning every
        // self-referential type at `.todo` — and the referencing law was still
        // proposed, often at Strong tier, so the tool made its most confident
        // claim and then could not run it.
        //
        // Instead, hand back the recursion *point*. `derive` sees it in the
        // resulting plan and wraps the whole thing in a depth-budgeted helper
        // (`RecursiveGeneratorEmitter`). Deliberately not memoized: the node is
        // only meaningful inside the declaration currently being built.
        if visiting.contains(name) {
            return DerivationStrategist.ComposedGenerator(
                plan: .selfReference(
                    typeName: name,
                    helperName: RecursiveGeneratorEmitter.helperName(for: name)
                )
            )
        }

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
        guard let shape = shapesByName[name] ?? unambiguousLeafMatch(for: name) else {
            return nil   // external / unknown / ambiguous leaf
        }

        let result = derive(shape, visiting: visiting)
        memo[name] = result
        return result
    }

    /// The nested type an unqualified reference names, when exactly one
    /// qualified shape carries that leaf. Ambiguous leaves resolve to nothing,
    /// matching the full-name rule.
    private func unambiguousLeafMatch(for name: String) -> TypeShape? {
        guard !name.contains("."), !ambiguousLeafNames.contains(name) else { return nil }
        return shapesByLeafName[name]
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
        let expression = GeneratorExpressionEmitter.expression(
            typeName: shape.name,
            strategy: strategy
        )

        // Did resolving the members lead back here? If so the expression now
        // contains this type's recursion point, and cannot stand on its own —
        // it has to become the body of a depth-budgeted helper that the stub
        // declares and the plan calls.
        if RecursiveGeneratorEmitter.isRecursive(expression: expression, typeName: shape.name) {
            guard let declaration = RecursiveGeneratorEmitter.declaration(
                typeName: shape.name,
                expression: expression
            ) else {
                // Recursion with no wrapper to terminate it (a bare `indirect
                // enum` payload). Unchanged behaviour: stay `.todo`.
                return nil
            }
            recursiveDeclarations[shape.name] = declaration
            return DerivationStrategist.ComposedGenerator(
                plan: .recursive(
                    typeName: shape.name,
                    helperName: RecursiveGeneratorEmitter.helperName(for: shape.name),
                    declaration: declaration,
                    imports: strategy.requiredImports
                )
            )
        }

        return DerivationStrategist.ComposedGenerator(
            expression: expression,
            requiredImports: strategy.requiredImports
        )
    }
}
