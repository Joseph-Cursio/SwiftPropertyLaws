import Testing
@testable import PropertyLawCore

/// Where a type offers `init(x: T)` and `init(xs: [T])`, the collection form is derived: one element is
/// a corner of the domain the collection form already includes.
struct CollectionInitializerPreferenceTests {

    private func shape(_ initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: "Big", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [], hasUserInit: true, initializers: initializers
        )
    }

    private func emitted(_ shape: TypeShape) -> String {
        GeneratorExpressionEmitter.expression(typeName: shape.name, strategy: DerivationStrategist.strategy(for: shape))
    }

    private func single(_ label: String, _ type: String) -> InitializerSignature {
        InitializerSignature(parameters: [InitializerParameter(label: label, typeName: type)])
    }

    @Test("a later [T] initializer is preferred over an earlier T one", arguments: ["[UInt]", "Array<UInt>"])
    func collectionIsPreferred(spelling: String) {
        let emitted = emitted(shape([single("word", "UInt"), single("words", spelling)]))
        #expect(emitted.contains("Big(words:"), "got: \(emitted)")
    }

    @Test("with no collection form, declaration order still decides")
    func orderStillDecides() {
        let emitted = emitted(shape([single("word", "UInt"), single("value", "Int")]))
        #expect(emitted.contains("Big(word:"), "got: \(emitted)")
    }

    @Test("a declined collection form leaves the scalar one")
    func declinedCollectionIsSkipped() {
        let throwing = InitializerSignature(
            parameters: [InitializerParameter(label: "words", typeName: "[UInt]")], isThrowing: true
        )
        let emitted = emitted(shape([single("word", "UInt"), throwing]))
        #expect(emitted.contains("Big(word:"), "got: \(emitted)")
    }

    @Test("a collection of a different element does not count")
    func differentElementDoesNotCount() {
        let emitted = emitted(shape([single("word", "UInt"), single("values", "[Int]")]))
        #expect(emitted.contains("Big(word:"), "got: \(emitted)")
    }
}
