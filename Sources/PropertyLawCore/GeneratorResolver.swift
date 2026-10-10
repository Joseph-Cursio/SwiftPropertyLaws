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

    /// Keyed by the name a spelling **found** — a shape's qualified name or an
    /// alias's key — never by the spelling itself, because one spelling names
    /// different types from different scopes: `Counted` is `BitSet.Counted`
    /// inside `BitSet` and nothing at all outside it.
    private var memo: [String: DerivationStrategist.ComposedGenerator?] = [:]

    /// Why each found name that derived to `nil` did so, keyed like `memo`.
    /// A spelling that found nothing needs no entry: `lookup` says why again.
    private var failures: [String: ResolutionFailure] = [:]

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
    /// `Gen.element(of: Foo.Kind.allCases)` already come out right. A bare
    /// spelling *inside* a scanned type reaches its nested namesakes through
    /// that type's scope; see `lookup(_:from:)`.
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

    /// Why `typeName` has no generator, or `nil` when it has one.
    ///
    /// Resolves the name first if nothing has asked yet, so the answer does not
    /// depend on what the caller happened to derive beforehand. The name is
    /// read at module scope, as `customTypeGenerator(forTypeName:)` reads it.
    public func resolutionFailure(forTypeName typeName: String) -> ResolutionFailure? {
        failure(for: typeName, from: nil)
    }

    /// Why `typeName`, written inside the type named `scope`, has no generator.
    ///
    /// The overload a `.noStrategy` reason needs: `Outer`'s reason names its
    /// member as written — `` `inner: Inner` resolves to no generator `` — and
    /// a bare `Inner` asked about at module scope is `.notInUniverse`, which is
    /// true there and says nothing about why `Outer.Inner` failed. Ask from
    /// `Outer` and the answer is `Outer.Inner`'s own.
    public func resolutionFailure(forTypeName typeName: String, within scope: String) -> ResolutionFailure? {
        failure(for: typeName, from: scope)
    }

    private func failure(for spelling: String, from scope: String?) -> ResolutionFailure? {
        guard resolve(spelling, from: scope, visiting: []) == nil else { return nil }
        switch lookup(spelling, from: scope) {
        case .failed(let failure): return failure
        case .alias(let key, _): return failures[key]
        case .shape(let shape): return failures[shape.name]
        }
    }

    /// Resolve closure for `DerivationStrategist.strategy(for:resolve:)` and
    /// `composedGenerator(forTypeName:resolve:)`: maps a custom-type spelling
    /// to its generator, recursing through the universe.
    ///
    /// The spelling is read **at module scope**, which is where the generated
    /// code that uses the answer is written: `BitSet.Counted` resolves, a bare
    /// `Counted` does not. To resolve a shape's *members*, pass
    /// `resolve(within: shape.name)` instead — they were written inside it.
    public func customTypeGenerator(
        forTypeName name: String
    ) -> DerivationStrategist.ComposedGenerator? {
        resolve(name, from: nil, visiting: [])
    }

    /// The resolve closure for spellings written **inside** the type named
    /// `scope`: a member or initializer parameter of that type, or anything in
    /// a function declared on it. Lookup starts at `scope` and works outward,
    /// so `Counted` written inside `BitSet` reaches `BitSet.Counted`.
    ///
    /// **This is the closure for `DerivationStrategist.strategy(for: shape,
    /// resolve:)`.** Passing `customTypeGenerator` there reads the shape's
    /// members at module scope, where a bare nested name means nothing; that
    /// went unnoticed while a leaf index guessed on every miss, and the guess
    /// is what SwiftPropertyLaws#63 removed.
    ///
    /// Not an overload of `customTypeGenerator`, deliberately: callers take that
    /// one unapplied (`let resolve = resolver.customTypeGenerator`), and a
    /// second overload would make every such reference ambiguous.
    public func resolve(within scope: String) -> DerivationStrategist.CustomTypeResolver {
        { name in self.resolve(name, from: scope, visiting: []) }
    }

    /// What one spelling refers to from one scope.
    private enum Lookup {
        case shape(TypeShape)
        case alias(key: String, underlying: String)
        case failed(ResolutionFailure)
    }

    /// What `spelling`, written inside the type named `scope`, refers to.
    ///
    /// **This is Swift's unqualified lookup, innermost scope first**: inside
    /// `A.B` the spelling `X` means `A.B.X`, else `A.X`, else a top-level `X`.
    /// `scope == nil` is module scope. A dotted spelling walks the same chain,
    /// so `Inner.Kind` written inside `Outer` reaches `Outer.Inner.Kind`.
    ///
    /// **It replaced a leaf index**, which answered a bare `Counted` with the
    /// one scanned type whose last component was `Counted`, wherever that type
    /// was nested. The index existed for the lexical case — `let x: Counted`
    /// inside `BitSet` means `BitSet.Counted`, which a flat universe cannot
    /// otherwise model — but it could not tell that case from a bare name
    /// meaning a type in **a module the scan does not contain**. SwiftAssist's
    /// `SymbolSummary.init(from symbol: Symbol)` takes SwiftSourceKitClient's
    /// `Symbol`; the only scanned `Symbol` was `XcodeDocument.Symbol`, nested in
    /// an unrelated type, so the resolver built one of those and the emitted
    /// call did not compile (SwiftPropertyLaws#63). The ambiguity rule could
    /// not catch it: the imported type is never scanned, so the universe saw
    /// one candidate. A name the scope chain does not reach is now
    /// `.notInUniverse`, which is what it is.
    ///
    /// Two further defects went with the index. **A top-level namesake used to
    /// shadow a nested type inside its own parent** — the index was consulted
    /// only after the full-name map missed, so `let c: Counted` inside `BitSet`
    /// built the top-level `Counted` whenever one existed, though Swift reads it
    /// as `BitSet.Counted`. And **a self-referential nested type reached through
    /// its leaf overflowed the stack**: the cycle guard compared the spelling
    /// `Node` against the in-progress `Outer.Node`, never matched, and derived
    /// again forever. Keying the guard on the name found closes that.
    ///
    /// Ambiguity is checked at each scope before moving outward, so a
    /// collision at an inner scope is reported rather than skipped over — Swift
    /// would stop there too.
    private func lookup(_ spelling: String, from scope: String?) -> Lookup {
        var enclosing = scope.map { $0.split(separator: ".").map(String.init) } ?? []
        while true {
            let candidate = (enclosing + [spelling]).joined(separator: ".")
            if ambiguousNames.contains(candidate) { return .failed(.ambiguous) }
            if let underlying = aliases[candidate] { return .alias(key: candidate, underlying: underlying) }
            if let shape = shapesByName[candidate] { return .shape(shape) }
            guard !enclosing.isEmpty else { return .failed(.notInUniverse) }
            enclosing.removeLast()
        }
    }

    private func resolve(
        _ spelling: String,
        from scope: String?,
        visiting: Set<String>
    ) -> DerivationStrategist.ComposedGenerator? {
        switch lookup(spelling, from: scope) {
        case .failed:
            return nil

        case .alias(let key, let underlying):
            return memoized(key, visiting: visiting) {
                // A user typealias → derive from its underlying type spelling,
                // read where the alias was declared: `Account.ID = Handle`
                // means whatever `Handle` means inside `Account`.
                let declaringScope = key.split(separator: ".").dropLast().joined(separator: ".")
                let result = DerivationStrategist.composedGenerator(forTypeName: underlying) { inner in
                    self.resolve(
                        inner,
                        from: declaringScope.isEmpty ? nil : declaringScope,
                        visiting: visiting.union([key])
                    )
                }
                if result == nil { failures[key] = .aliasUnresolved(underlying: underlying) }
                return result
            }

        case .shape(let shape):
            return memoized(shape.name, visiting: visiting) { derive(shape, visiting: visiting) }
        }
    }

    /// `compute`'s answer for the found `name`, at most once per resolver —
    /// unless `name` is already being derived further up, which is a cycle.
    private func memoized(
        _ name: String,
        visiting: Set<String>,
        compute: () -> DerivationStrategist.ComposedGenerator?
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

        let result = compute()
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
        // Every spelling in the shape was written inside it, so it is read from
        // the shape's own scope outward.
        let strategy = DerivationStrategist.strategy(for: shape) { inner in
            self.resolve(inner, from: shape.name, visiting: nextVisiting)
        }
        if case .todo(let reason) = strategy {
            failures[shape.name] = .noStrategy(reason: reason)
            return nil
        }
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
                failures[shape.name] = .unterminatedRecursion
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
