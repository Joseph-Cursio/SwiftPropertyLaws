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
                == "Gen<Direction>.element(of: Direction.allCases).map { Holder(dir: $0) }"
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
}
