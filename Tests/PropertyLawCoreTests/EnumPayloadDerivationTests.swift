import Testing
@testable import PropertyLawCore

/// Tier 4: enums with cases (payload-bearing or plain, but not
/// `CaseIterable`/raw) now derive a `Gen.oneOf(...)` over per-case
/// generators, instead of `.todo`. These tests pin the strategy + emitted
/// expression for hand-built `TypeShape`s; SwiftSyntax extraction lands
/// separately.
struct EnumPayloadDerivationTests {

    private func enumShape(
        _ name: String,
        cases: [EnumCase],
        inheritedTypes: [String] = ["Equatable"]
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: .enum,
            inheritedTypes: inheritedTypes,
            hasUserGen: false,
            enumCases: cases
        )
    }

    private func emitted(_ shape: TypeShape) -> String {
        GeneratorExpressionEmitter.expression(
            typeName: shape.name,
            strategy: DerivationStrategist.strategy(for: shape)
        )
    }

    private func value(_ label: String?, _ type: String) -> InitializerParameter {
        InitializerParameter(label: label, typeName: type)
    }

    // MARK: - Payload-free

    @Test func multipleplainCasesCombineWithOneOf() {
        let shape = enumShape("Color", cases: [
            EnumCase(name: "red"), EnumCase(name: "green"), EnumCase(name: "blue")
        ])
        let expected = """
            Gen.oneOf(
                Gen.always(Color.red).eraseToAny(),
                Gen.always(Color.green).eraseToAny(),
                Gen.always(Color.blue).eraseToAny()
            )
            """
        #expect(emitted(shape) == expected)
    }

    @Test func singlePlainCaseEmitsAlwaysDirectly() {
        let shape = enumShape("Unit", cases: [EnumCase(name: "only")])
        #expect(emitted(shape) == "Gen.always(Unit.only)")
    }

    // MARK: - Payloads

    @Test func singleCaseWithLabeledValuesZips() {
        let shape = enumShape("Point", cases: [
            EnumCase(name: "xy", associatedValues: [value("x", "Int"), value("y", "Int")])
        ])
        let expected = """
            zip(Gen<Int>.int(), Gen<Int>.int())
                        .map { Point.xy(x: $0.0, y: $0.1) }
            """
        #expect(emitted(shape) == expected)
    }

    @Test func unlabeledAssociatedValueOmitsLabel() {
        let shape = enumShape("Box", cases: [
            EnumCase(name: "wrap", associatedValues: [value(nil, "Int")])
        ])
        #expect(emitted(shape) == "Gen<Int>.int().map { Box.wrap($0) }")
    }

    @Test func mixedPlainAndPayloadCases() {
        let shape = enumShape("Shape", cases: [
            EnumCase(name: "empty"),
            EnumCase(name: "circle", associatedValues: [value("radius", "Int")])
        ])
        let expected = """
            Gen.oneOf(
                Gen.always(Shape.empty).eraseToAny(),
                Gen<Int>.int().map { Shape.circle(radius: $0) }.eraseToAny()
            )
            """
        #expect(emitted(shape) == expected)
    }

    @Test func dateAssociatedValueRequiresFoundation() {
        let shape = enumShape("Event", cases: [
            EnumCase(name: "at", associatedValues: [value(nil, "Date")])
        ])
        #expect(DerivationStrategist.strategy(for: shape).requiredImports == ["Foundation"])
    }

    // MARK: - Nested custom associated value (Tier 3 interplay)

    @Test func nestedCustomAssociatedValueResolvesViaResolver() {
        let customer = TypeShape(
            name: "Customer", kind: .struct, inheritedTypes: ["Equatable"],
            hasUserGen: false, storedMembers: [StoredMember(name: "name", typeName: "String")]
        )
        let event = enumShape("Event", cases: [
            EnumCase(name: "placed", associatedValues: [value(nil, "Customer")])
        ])
        let resolver = GeneratorResolver(types: [customer, event])
        let strategy = DerivationStrategist.strategy(for: event, resolve: resolver.customTypeGenerator)
        guard case .enumCases = strategy else {
            Issue.record("expected enumCases via nested resolution")
            return
        }
    }

    // MARK: - Fall-through

    @Test func nonDerivableAssociatedValueFallsThrough() {
        let shape = enumShape("Doc", cases: [
            EnumCase(name: "at", associatedValues: [value(nil, "Widget")])
        ])
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for non-derivable associated value")
            return
        }
    }

    @Test func emptyCaptureFallsThroughToTodo() {
        // No cases captured (pre-Tier-4 shape) → unchanged .todo behavior.
        let shape = enumShape("Either", cases: [])
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo when no cases captured")
            return
        }
    }

    // MARK: - Priority: CaseIterable / raw still win

    @Test func caseIterableWinsOverEnumCases() {
        let shape = enumShape("E", cases: [EnumCase(name: "a")], inheritedTypes: ["CaseIterable"])
        #expect(DerivationStrategist.strategy(for: shape) == .caseIterable)
    }

    @Test func rawRepresentableWinsOverEnumCases() {
        let shape = enumShape("E", cases: [EnumCase(name: "a")], inheritedTypes: ["Int"])
        #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(.int))
    }
}
