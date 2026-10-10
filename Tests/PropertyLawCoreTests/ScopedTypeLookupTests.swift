import Testing
@testable import PropertyLawCore

/// `GeneratorResolver` reads a spelling the way Swift does: from the scope it
/// was written in, innermost first, then module scope — never from an unrelated
/// nested type that happens to share its last component (SwiftPropertyLaws#63).
///
/// The leaf index this replaced answered a bare `Symbol` with the only scanned
/// type ending in `.Symbol`, wherever it was nested. That was right for
/// `let c: Counted` inside `BitSet`, and wrong when the name came from **a
/// module the scan did not contain**: SwiftAssist's
/// `SymbolSummary.init(from symbol: Symbol)` takes SwiftSourceKitClient's
/// `Symbol`, and the resolver built an `XcodeDocument.Symbol` for it — the one
/// reference-oracle scaffold out of 67 in that census that did not compile.
struct ScopedTypeLookupTests {

    private func shape(
        _ name: String,
        _ members: [(String, String)] = [],
        initializers: [InitializerSignature] = []
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members.map { StoredMember(name: $0.0, typeName: $0.1) },
            hasUserInit: !initializers.isEmpty,
            initializers: initializers
        )
    }

    // MARK: - The regression pair from the issue

    /// The issue's reproduction, verbatim.
    @Test("a bare name from another module does not take an unrelated nested type")
    func foreignNameIsNotAScannedLeaf() {
        let resolver = GeneratorResolver(types: [
            shape("Document.Symbol", [("id", "Int")]),
            shape("Summary", [("symbol", "Symbol")])
        ])
        #expect(resolver.customTypeGenerator(forTypeName: "Summary") == nil)
        #expect(resolver.resolutionFailure(forTypeName: "Symbol", within: "Summary") == .notInUniverse)
    }

    /// The form it was seen in: an initializer parameter, not a stored member.
    @Test("an init parameter from another module does not take an unrelated nested type")
    func foreignInitParameterIsNotAScannedLeaf() {
        let summary = shape("SemanticMap.SymbolSummary", initializers: [
            InitializerSignature(parameters: [InitializerParameter(label: "from", typeName: "Symbol")])
        ])
        let resolver = GeneratorResolver(types: [shape("XcodeDocument.Symbol", [("id", "Int")]), summary])
        let strategy = DerivationStrategist.strategy(for: summary, resolve: resolver.resolve(within: summary.name))
        guard case .todo = strategy else {
            Issue.record("expected .todo; got \(strategy)")
            return
        }
    }

    /// The lexical case the leaf index existed for, and must keep.
    @Test("a bare name inside its parent reaches the nested type")
    func lexicalNameStillResolves() {
        let resolver = GeneratorResolver(types: [
            shape("BitSet.Counted", [("n", "Int")]),
            shape("BitSet", [("counted", "Counted")])
        ])
        #expect(
            resolver.customTypeGenerator(forTypeName: "BitSet")?.expression
                == "Gen<Int>.int().map { BitSet.Counted(n: $0) }.map { BitSet(counted: $0) }"
        )
    }

    /// The same, through the call the discovery plugin makes: it derives each
    /// entry's own strategy and passes the resolver as the closure.
    @Test("a shape's own members are read from inside it")
    func scopedClosureReadsFromInsideTheShape() {
        let bitSet = shape("BitSet", [("counted", "Counted")])
        let resolver = GeneratorResolver(types: [shape("BitSet.Counted", [("n", "Int")]), bitSet])
        guard case .memberwiseArbitrary(let members) = DerivationStrategist.strategy(
            for: bitSet, resolve: resolver.resolve(within: bitSet.name)
        ) else {
            Issue.record("BitSet should derive through BitSet.Counted")
            return
        }
        #expect(members.first?.generatorExpression == "Gen<Int>.int().map { BitSet.Counted(n: $0) }")
        // At module scope the bare name names nothing.
        #expect(resolver.customTypeGenerator(forTypeName: "Counted") == nil)
    }

    // MARK: - The scope chain

    /// Swift reads `Counted` inside `BitSet` as `BitSet.Counted` even when a
    /// top-level `Counted` exists. The leaf index was consulted only after the
    /// full-name map missed, so the top-level namesake used to win here.
    @Test("a nested type shadows a top-level namesake inside its parent")
    func nestedShadowsTopLevelInsideParent() {
        let resolver = GeneratorResolver(types: [
            shape("Counted", [("s", "String")]),
            shape("BitSet.Counted", [("n", "Int")]),
            shape("BitSet", [("counted", "Counted")]),
            shape("User", [("counted", "Counted")])
        ])
        let inside = resolver.customTypeGenerator(forTypeName: "BitSet")?.expression ?? ""
        #expect(inside.contains("BitSet.Counted(n:"))
        let outside = resolver.customTypeGenerator(forTypeName: "User")?.expression ?? ""
        #expect(outside.contains("{ Counted(s:"))
    }

    /// Lookup walks every enclosing scope, not just the type's own.
    @Test("a name reaches a sibling nested in an enclosing type")
    func walksOutwardThroughEnclosingScopes() {
        let resolver = GeneratorResolver(types: [
            shape("A.C", [("n", "Int")]),
            shape("A.B", [("c", "C")])
        ])
        #expect(
            resolver.customTypeGenerator(forTypeName: "A.B")?.expression
                == "Gen<Int>.int().map { A.C(n: $0) }.map { A.B(c: $0) }"
        )
    }

    /// A dotted spelling walks the same chain: `Inner.Kind` inside `Outer`.
    @Test("a partly qualified name resolves from an enclosing scope")
    func dottedSpellingWalksTheChain() {
        let resolver = GeneratorResolver(types: [
            shape("Outer.Inner.Kind", [("n", "Int")]),
            shape("Outer", [("kind", "Inner.Kind")])
        ])
        #expect(
            resolver.customTypeGenerator(forTypeName: "Outer")?.expression
                == "Gen<Int>.int().map { Outer.Inner.Kind(n: $0) }.map { Outer(kind: $0) }"
        )
    }

    /// Swift stops at the innermost scope that declares the name, so a
    /// collision there is the answer — not a reason to keep walking outward to
    /// an unambiguous top-level namesake.
    @Test("a collision at an inner scope is ambiguous, not skipped")
    func innerCollisionIsAmbiguous() {
        let resolver = GeneratorResolver(types: [
            shape("Kind", [("top", "Int")]),
            shape("Outer.Kind", [("a", "Int")]),
            shape("Outer.Kind", [("b", "String")]),
            shape("Outer", [("kind", "Kind")])
        ])
        #expect(resolver.resolutionFailure(forTypeName: "Kind", within: "Outer") == .ambiguous)
        #expect(resolver.customTypeGenerator(forTypeName: "Outer") == nil)
        #expect(resolver.customTypeGenerator(forTypeName: "Kind") != nil)
    }

    /// An alias's right-hand side was written where the alias was declared.
    @Test("a nested alias resolves its underlying spelling from its declaring type")
    func nestedAliasReadsFromItsDeclaringScope() {
        let resolver = GeneratorResolver(
            types: [shape("Account.Handle", [("raw", "Int")]), shape("Account", [("id", "ID")])],
            aliases: ["Account.ID": "Handle"]
        )
        #expect(
            resolver.customTypeGenerator(forTypeName: "Account")?.expression
                == "Gen<Int>.int().map { Account.Handle(raw: $0) }.map { Account(id: $0) }"
        )
    }

    // MARK: - Recursion

    /// This used to overflow the stack. The cycle guard compared the spelling
    /// `Node` with the in-progress `Outer.Node`, never matched, and the leaf
    /// index sent it round again. The guard now keys on the name found.
    @Test("a self-referential nested type terminates and gets its helper")
    func nestedSelfReferenceTerminates() {
        let resolver = GeneratorResolver(types: [shape("Outer.Node", [("value", "Int"), ("next", "Node?")])])
        #expect(resolver.customTypeGenerator(forTypeName: "Outer.Node")?.expression == "__genOuterNode(4)")
        #expect(resolver.isRecursive("Outer.Node"))
        #expect(resolver.supportingDeclarations.count == 1)
    }
}
