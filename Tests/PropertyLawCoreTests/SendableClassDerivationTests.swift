import Testing
@testable import PropertyLawCore

/// A class that declares `Sendable` derives through its initializer, exactly as a struct with a
/// user `init` does. Every draw calls the initializer, so each trial gets a fresh instance and no
/// state carries between them.
///
/// `Sendable` is the whole condition, not a style preference: `PropertyBackend.check` requires
/// `Input: Sendable`, so a generator for a non-`Sendable` class could be written and never used.
/// Actors stay out, because calling into one needs `await` and a derived generator's consumers
/// call synchronously. The stateless tier stays struct-only, because `Gen.always(T())` would hand
/// every draw the same instance.
///
/// Measured downstream: SwiftInferProperties' seventh corpus census set aside 16 stub markers on
/// `Sendable` classes (Fluent models such as `final class User: Model, @unchecked Sendable`).
struct SendableClassDerivationTests {

    private func classShape(
        _ name: String,
        kind: TypeShape.Kind = .class,
        inheritedTypes: [String],
        initializers: [InitializerSignature]
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: kind,
            inheritedTypes: inheritedTypes,
            hasUserGen: false,
            storedMembers: [StoredMember(name: "email", typeName: "String")],
            hasUserInit: !initializers.isEmpty,
            initializers: initializers
        )
    }

    private let emailInit = InitializerSignature(parameters: [
        InitializerParameter(label: "email", typeName: "String")
    ])

    private func reason(_ shape: TypeShape) -> String? {
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else { return nil }
        return reason
    }

    @Test func uncheckedSendableClassDerivesThroughItsInitializer() {
        let shape = classShape("User", inheritedTypes: ["Model", "@unchecked Sendable"], initializers: [emailInit])
        let expression = GeneratorExpressionEmitter.expression(
            typeName: shape.name,
            strategy: DerivationStrategist.strategy(for: shape)
        )
        #expect(expression == "Gen<Character>.letterOrNumber.string(of: 0...8).map { User(email: $0) }")
    }

    @Test func plainSendableClassDerivesThroughItsInitializer() {
        let shape = classShape("Handle", inheritedTypes: ["Sendable"], initializers: [emailInit])
        guard case .initializerBased = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected a Sendable class to derive through its initializer")
            return
        }
    }

    @Test func nonSendableClassDeclinesAndSaysWhy() {
        let shape = classShape("Visitor", inheritedTypes: ["SyntaxVisitor"], initializers: [emailInit])
        let text = reason(shape)
        #expect(text?.contains("Sendable") == true, "the reason must name the actual condition")
        #expect(text?.contains("structs only") == false, "a class with an initializer is not refused for being a class")
    }

    @Test func actorStillDeclines() {
        let shape = classShape("Store", kind: .actor, inheritedTypes: ["Sendable"], initializers: [emailInit])
        #expect(reason(shape) != nil)
    }

    @Test func sendableClassWithoutAnInitializerDoesNotShareOneInstance() {
        let shape = classShape("Cache", inheritedTypes: ["Sendable"], initializers: [])
        #expect(reason(shape) != nil, "Gen.always(Cache()) would hand every draw the same instance")
    }

    @Test func sendableIsMatchedAsAWholeWordOnly() {
        let shape = classShape("Box", inheritedTypes: ["NotSendableMarker"], initializers: [emailInit])
        #expect(reason(shape) != nil)
    }
}
