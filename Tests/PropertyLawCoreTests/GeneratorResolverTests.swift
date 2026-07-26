import Testing
@testable import PropertyLawCore

/// Tier 3: nested custom-type derivation through a whole-module
/// `GeneratorResolver`. A member or init parameter typed as a sibling custom
/// type now resolves (inlining that type's generator, or referencing its
/// `gen()`), instead of dead-ending at `.todo`. External types and recursive
/// cycles stay `.todo`.
struct GeneratorResolverTests {

    private func structShape(
        _ name: String,
        _ members: [(String, String)],
        hasUserGen: Bool = false
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: hasUserGen,
            storedMembers: members.map { StoredMember(name: $0.0, typeName: $0.1) }
        )
    }

    private func strategy(for name: String, in universe: [TypeShape]) -> DerivationStrategy {
        let resolver = GeneratorResolver(types: universe)
        let shape = universe.first { $0.name == name }!
        return DerivationStrategist.strategy(for: shape, resolve: resolver.customTypeGenerator)
    }

    private func expression(for name: String, in universe: [TypeShape]) -> String {
        GeneratorExpressionEmitter.expression(
            typeName: name,
            strategy: strategy(for: name, in: universe)
        )
    }

    // MARK: - Nested struct inlines the nested generator

    @Test func nestedStructMemberInlinesItsGenerator() {
        let customer = structShape("Customer", [("name", "String")])
        let order = structShape("Order", [("id", "Int"), ("customer", "Customer")])
        let expected = """
            zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8).map { Customer(name: $0) })
                        .map { Order(id: $0.0, customer: $0.1) }
            """
        #expect(expression(for: "Order", in: [order, customer]) == expected)
    }

    @Test func nestedCustomInsideArrayComposes() {
        let customer = structShape("Customer", [("name", "String")])
        let cart = structShape("Cart", [("items", "[Customer]")])
        #expect(
            expression(for: "Cart", in: [cart, customer])
                == "Gen<Character>.letterOrNumber.string(of: 0...8)"
                + ".map { Customer(name: $0) }.array(of: 0...8).map { Cart(items: $0) }"
        )
    }

    // MARK: - User gen() reference

    @Test func nestedTypeWithUserGenIsReferenced() {
        let customer = structShape("Customer", [("name", "String")], hasUserGen: true)
        let order = structShape("Order", [("customer", "Customer")])
        #expect(expression(for: "Order", in: [order, customer]) == "Customer.gen().map { Order(customer: $0) }")
    }

    // MARK: - Nested CaseIterable enum

    @Test func nestedCaseIterableEnumResolves() {
        let direction = TypeShape(
            name: "Direction",
            kind: .enum,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: false
        )
        let holder = structShape("Holder", [("dir", "Direction")])
        #expect(
            expression(for: "Holder", in: [holder, direction])
                == "Gen<Direction?>.element(of: Direction.allCases).compactMap { $0 }.map { Holder(dir: $0) }"
        )
    }

    // MARK: - Initializer-based nesting

    @Test func initializerParameterResolvesNestedType() {
        let customer = structShape("Customer", [("name", "String")])
        let box = TypeShape(
            name: "Box",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: [
                InitializerParameter(label: "customer", typeName: "Customer")
            ])]
        )
        guard case .initializerBased = strategy(for: "Box", in: [box, customer]) else {
            Issue.record("expected initializerBased through nested resolution")
            return
        }
    }

    // MARK: - Import propagation

    @Test func nestedFoundationImportPropagates() {
        let stamped = structShape("Stamped", [("at", "Date")])
        let wrapper = structShape("Wrapper", [("inner", "Stamped")])
        #expect(strategy(for: "Wrapper", in: [wrapper, stamped]).requiredImports == ["Foundation"])
    }

    // MARK: - Non-resolvable: external types and cycles → .todo

    @Test func externalTypeNotInUniverseFallsThrough() {
        let order = structShape("Order", [("customer", "Customer")])
        guard case .todo = strategy(for: "Order", in: [order]) else {
            Issue.record("expected .todo for a type not in the universe")
            return
        }
    }

    @Test func selfRecursiveTypeFallsThrough() {
        let node = structShape("Node", [("value", "Int"), ("next", "Node")])
        guard case .todo = strategy(for: "Node", in: [node]) else {
            Issue.record("expected .todo for a self-recursive type")
            return
        }
    }

    @Test func mutualRecursionFallsThrough() {
        let typeA = structShape("A", [("b", "B")])
        let typeB = structShape("B", [("a", "A")])
        guard case .todo = strategy(for: "A", in: [typeA, typeB]) else {
            Issue.record("expected .todo for mutually recursive types")
            return
        }
    }

    // MARK: - User typealias resolution

    @Test func userTypealiasResolvesToUnderlyingGenerator() {
        let resolver = GeneratorResolver(types: [], aliases: ["UserID": "Int"])
        #expect(resolver.customTypeGenerator(forTypeName: "UserID")?.expression == "Gen<Int>.int()")
    }

    @Test func userTypealiasToCompositeResolves() {
        let resolver = GeneratorResolver(types: [], aliases: ["Coords": "[Double]"])
        #expect(
            resolver.customTypeGenerator(forTypeName: "Coords")?.expression
                == "Gen<Double>.double(in: -1_000_000...1_000_000).array(of: 0...8)"
        )
    }

    @Test func memberTypedAsUserAliasDerivesMemberwise() {
        let account = structShape("Account", [("id", "UserID"), ("name", "String")])
        let resolver = GeneratorResolver(types: [account], aliases: ["UserID": "Int"])
        guard case .memberwiseArbitrary = strategyResolving(account, with: resolver) else {
            Issue.record("expected memberwise derivation through the alias")
            return
        }
    }

    private func strategyResolving(_ shape: TypeShape, with resolver: GeneratorResolver) -> DerivationStrategy {
        DerivationStrategist.strategy(for: shape, resolve: resolver.customTypeGenerator)
    }

    // MARK: - Macro path (no resolver) is unchanged

    @Test func withoutResolverNestedCustomStaysTodo() {
        let order = structShape("Order", [("customer", "Customer")])
        guard case .todo = DerivationStrategist.strategy(for: order) else {
            Issue.record("expected .todo without a resolver (macro path)")
            return
        }
    }

    // MARK: - Ambiguous bare names are refused, not guessed
    //
    // `TypeShape.name` is one unqualified string, so a scanner that records
    // nested types under their bare names hands the resolver several distinct
    // shapes all called `Kind`. The universe used to be built with
    // `uniquingKeysWith: { first, _ in first }` — it silently kept whichever
    // arrived first, and a member typed `Kind` on one type could be generated
    // from an unrelated type's nested enum, with no diagnostic anywhere.
    //
    // SwiftInferProperties' self-dogfood road test is where this surfaced:
    // **eight** distinct types named `Kind`, collapsed to one, and the survivor
    // was a CLI-internal enum unrelated to any of the members referencing it.
    // These tests pin the refusal.

    private func enumShape(_ name: String, inheriting: [String]) -> TypeShape {
        TypeShape(name: name, kind: .enum, inheritedTypes: inheriting, hasUserGen: false)
    }

    @Test func twoDistinctTypesSharingABareNameResolveToNothing() {
        // Two different `Kind`s — as `Foo.Kind` and `Bar.Kind` would arrive from
        // a scanner that records nested types unqualified.
        let universe = [
            enumShape("Kind", inheriting: ["String", "CaseIterable"]),
            enumShape("Kind", inheriting: ["Int", "Codable"])
        ]
        let resolver = GeneratorResolver(types: universe)
        #expect(
            resolver.customTypeGenerator(forTypeName: "Kind") == nil,
            "an ambiguous name must resolve to nothing rather than to whichever shape came first"
        )
    }

    @Test func ambiguousNamesAreReportedSoAScannerCanExplainTheTodo() {
        let universe = [
            enumShape("Kind", inheriting: ["String", "CaseIterable"]),
            enumShape("Kind", inheriting: ["Int", "Codable"]),
            structShape("Order", [("id", "Int")])
        ]
        let resolver = GeneratorResolver(types: universe)
        #expect(resolver.ambiguousTypeNames == ["Kind"])
        // Unambiguous names in the same universe are unaffected.
        #expect(resolver.customTypeGenerator(forTypeName: "Order") != nil)
    }

    @Test func aMemberTypedAsAnAmbiguousNameKeepsItsOwnerAtTodo() {
        let universe = [
            enumShape("Kind", inheriting: ["String", "CaseIterable"]),
            enumShape("Kind", inheriting: ["Int", "Codable"]),
            structShape("Entry", [("name", "String"), ("kind", "Kind")])
        ]
        let entry = universe.last!
        guard case .todo = strategy(for: "Entry", in: universe) else {
            Issue.record("a member of ambiguous type must leave its owner non-derivable")
            return
        }
        _ = entry
    }

    /// The same shape scanned twice is **not** ambiguity — a universe assembled
    /// from overlapping scans must still resolve. Without this, the refusal
    /// above would turn every duplicate-free-but-rescanned type into a `.todo`
    /// and quietly gut derivation.
    @Test func anIdenticalDuplicateIsNotAmbiguity() {
        let side = enumShape("Side", inheriting: ["String", "CaseIterable"])
        let resolver = GeneratorResolver(types: [side, side])
        #expect(resolver.ambiguousTypeNames.isEmpty)
        #expect(
            resolver.customTypeGenerator(forTypeName: "Side")?.expression
                == "Gen<Side?>.element(of: Side.allCases).compactMap { $0 }"
        )
    }

    /// The escape hatch, and the reason refusing is safe: a caller that records
    /// nested types by **qualified** name has no collision, and every emitter
    /// interpolates the name verbatim, so `Foo.Kind` comes out spelled
    /// correctly with no change to the emitters at all.
    @Test func qualifiedNamesDisambiguateAndEmitCorrectly() {
        let universe = [
            enumShape("Foo.Kind", inheriting: ["String", "CaseIterable"]),
            enumShape("Bar.Kind", inheriting: ["String", "CaseIterable"]),
            structShape("Entry", [("name", "String"), ("kind", "Foo.Kind")])
        ]
        let resolver = GeneratorResolver(types: universe)
        #expect(resolver.ambiguousTypeNames.isEmpty)
        #expect(
            resolver.customTypeGenerator(forTypeName: "Foo.Kind")?.expression
                == "Gen<Foo.Kind?>.element(of: Foo.Kind.allCases).compactMap { $0 }"
        )
        // …and the enclosing type now derives, referencing the qualified name.
        let expr = expression(for: "Entry", in: universe)
        #expect(expr.contains("Foo.Kind.allCases"))
        #expect(!expr.contains("Bar.Kind"))
    }
}
