import Testing
@testable import PropertyLawCore

/// Generator scaffolding (Phases 2–3): a partially-derivable type yields a
/// `gen()` stub with the derivable slots filled and the rest as placeholders;
/// fully-derivable and non-scaffoldable types yield `nil`.
struct ScaffoldEmitterTests {

    private func structShape(
        _ name: String,
        _ members: [(String, String)],
        kind: TypeShape.Kind = .struct
    ) -> TypeShape {
        TypeShape(
            name: name, kind: kind, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: members.map { StoredMember(name: $0.0, typeName: $0.1) }
        )
    }

    // MARK: - Scaffolds produced

    @Test func partialStructFillsKnownSlotsAndHolesTheRest() {
        let doc = structShape("Doc", [("id", "Int"), ("widget", "Widget")])
        let stub = try? #require(ScaffoldEmitter.stub(for: doc))
        let text = stub ?? ""
        #expect(text.contains("extension Doc {"))
        #expect(text.contains("static func gen() -> Generator<Doc, some SendableSequenceType>"))
        #expect(text.contains("Gen<Int>.int()"))               // id resolved
        #expect(text.contains("<#Generator<Widget>#>"))        // widget placeholder
        #expect(text.contains("Doc(id: $0.0, widget: $0.1)"))  // lifted through the init
    }

    @Test func holeInsideCollectionKeepsStructure() {
        let cart = structShape("Cart", [("items", "[Color]")])
        let text = ScaffoldEmitter.stub(for: cart) ?? ""
        // The array structure is preserved around the placeholder element.
        #expect(text.contains("<#Generator<Color>#>.array(of: 0...8)"))
    }

    @Test func userInitScaffoldsThroughThatInit() {
        let shape = TypeShape(
            name: "Money", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: [
                InitializerParameter(label: "amount", typeName: "Int"),
                InitializerParameter(label: "currency", typeName: "Currency")
            ])]
        )
        let text = ScaffoldEmitter.stub(for: shape) ?? ""
        #expect(text.contains("Gen<Int>.int()"))
        #expect(text.contains("<#Generator<Currency>#>"))
        #expect(text.contains("Money(amount: $0.0, currency: $0.1)"))
    }

    @Test func enumWithUnresolvablePayloadScaffolds() {
        let shape = TypeShape(
            name: "Node", kind: .enum, inheritedTypes: ["Equatable"], hasUserGen: false,
            enumCases: [EnumCase(name: "leaf", associatedValues: [
                InitializerParameter(label: nil, typeName: "Widget")
            ])]
        )
        let text = ScaffoldEmitter.stub(for: shape) ?? ""
        #expect(text.contains("<#Generator<Widget>#>.map { Node.leaf($0) }"))
    }

    // MARK: - No scaffold (nil)

    @Test func fullyDerivableTypeNeedsNoScaffold() {
        let point = structShape("Point", [("x", "Int"), ("y", "Int")])
        #expect(ScaffoldEmitter.stub(for: point) == nil)
    }

    @Test func classIsNotScaffoldable() {
        let box = structShape("Box", [("value", "Int")], kind: .class)
        #expect(ScaffoldEmitter.stub(for: box) == nil)
    }

    @Test func emptyStructIsNotScaffoldable() {
        let empty = structShape("Empty", [])
        #expect(ScaffoldEmitter.stub(for: empty) == nil)
    }

    // MARK: - Nested derivable type is inlined, not holed

    @Test func nestedDerivableTypeIsInlinedNotPlaceholdered() {
        let customer = structShape("Customer", [("name", "String")])
        let order = structShape("Order", [("id", "Int"), ("customer", "Customer")])
        let resolver = GeneratorResolver(types: [customer, order])
        // Order fully derives once Customer resolves → no scaffold needed.
        #expect(ScaffoldEmitter.stub(for: order, resolve: resolver.customTypeGenerator) == nil)
    }
}
