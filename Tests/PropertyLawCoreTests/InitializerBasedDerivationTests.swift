import Testing
@testable import PropertyLawCore

/// Tier 6: structs with a user-defined initializer (which suppresses Swift's
/// synthesized memberwise init) now derive by lifting through that init,
/// instead of falling through to `.todo` — the dominant `.todo` category on
/// real code. These tests pin the strategy + emitted expression for
/// hand-built `TypeShape`s; the SwiftSyntax extraction lands separately.
struct InitializerBasedDerivationTests {

    private func structShape(
        _ name: String,
        initializers: [InitializerSignature],
        storedMembers: [StoredMember] = []
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: storedMembers,
            hasUserInit: true,
            initializers: initializers
        )
    }

    private func emitted(_ shape: TypeShape) -> String {
        GeneratorExpressionEmitter.expression(
            typeName: shape.name,
            strategy: DerivationStrategist.strategy(for: shape)
        )
    }

    // MARK: - Happy paths

    @Test func singleLabeledParameter() {
        let shape = structShape("Box", initializers: [
            InitializerSignature(parameters: [InitializerParameter(label: "value", typeName: "Int")])
        ])
        #expect(emitted(shape) == "Gen<Int>.int().map { Box(value: $0) }")
    }

    @Test func twoLabeledParametersZip() {
        let shape = structShape("User", initializers: [
            InitializerSignature(parameters: [
                InitializerParameter(label: "name", typeName: "String"),
                InitializerParameter(label: "count", typeName: "Int")
            ])
        ])
        let expected = """
            zip(Gen<Character>.letterOrNumber.string(of: 0...8), Gen<Int>.int())
                        .map { User(name: $0.0, count: $0.1) }
            """
        #expect(emitted(shape) == expected)
    }

    @Test func unlabeledParameterOmitsLabel() {
        let shape = structShape("Identifier", initializers: [
            InitializerSignature(parameters: [InitializerParameter(label: nil, typeName: "Int")])
        ])
        #expect(emitted(shape) == "Gen<Int>.int().map { Identifier($0) }")
    }

    @Test func mixedLabeledAndUnlabeledParameters() {
        let shape = structShape("Tagged", initializers: [
            InitializerSignature(parameters: [
                InitializerParameter(label: nil, typeName: "Int"),
                InitializerParameter(label: "label", typeName: "String")
            ])
        ])
        let expected = """
            zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8))
                        .map { Tagged($0.0, label: $0.1) }
            """
        #expect(emitted(shape) == expected)
    }

    @Test func compositeAndDateParametersComposeAndCarryImports() {
        let shape = structShape("Event", initializers: [
            InitializerSignature(parameters: [
                InitializerParameter(label: "tags", typeName: "[String]"),
                InitializerParameter(label: "at", typeName: "Date")
            ])
        ])
        let strategy = DerivationStrategist.strategy(for: shape)
        guard case .initializerBased = strategy else {
            Issue.record("expected initializerBased")
            return
        }
        #expect(strategy.requiredImports == ["Foundation"])
    }

    // MARK: - Initializer selection

    @Test func skipsFailableAndThrowingPicksDerivableInit() {
        let shape = structShape("Money", initializers: [
            InitializerSignature(
                parameters: [InitializerParameter(label: "raw", typeName: "String")],
                isFailable: true
            ),
            InitializerSignature(
                parameters: [InitializerParameter(label: "cents", typeName: "Int")],
                isThrowing: true
            ),
            InitializerSignature(parameters: [InitializerParameter(label: "cents", typeName: "Int")])
        ])
        #expect(emitted(shape) == "Gen<Int>.int().map { Money(cents: $0) }")
    }

    @Test func memberwiseStillWinsWhenNoUserInit() {
        // No user init → memberwise path, not initializerBased.
        let shape = TypeShape(
            name: "Plain",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "x", typeName: "Int")],
            hasUserInit: false
        )
        guard case .memberwiseArbitrary = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected memberwise when there is no user init")
            return
        }
    }

    // MARK: - Fall-through to .todo

    @Test func nonDerivableParameterFallsThroughWithInitReason() {
        let shape = structShape(
            "Doc",
            initializers: [
                InitializerSignature(parameters: [InitializerParameter(label: "widget", typeName: "Widget")])
            ],
            storedMembers: [StoredMember(name: "widget", typeName: "Widget")]
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for non-derivable init parameter")
            return
        }
        #expect(reason.contains("user `init"))
        #expect(reason.contains("resolve to a recognized generator"))
    }

    @Test func arityOverLimitIsSkipped() {
        // Nested composition raised the init-parameter ceiling from 10 to 100;
        // 101 still exceeds it.
        let params = (0..<101).map { InitializerParameter(label: "p\($0)", typeName: "Int") }
        let shape = structShape(
            "Absurd",
            initializers: [InitializerSignature(parameters: params)],
            storedMembers: [StoredMember(name: "p0", typeName: "Int")]
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo at init arity 101")
            return
        }
    }

    @Test func emptyParameterInitIsSkipped() {
        let shape = structShape(
            "Empty",
            initializers: [InitializerSignature(parameters: [])],
            storedMembers: [StoredMember(name: "x", typeName: "Int")]
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for zero-parameter init")
            return
        }
    }
}
