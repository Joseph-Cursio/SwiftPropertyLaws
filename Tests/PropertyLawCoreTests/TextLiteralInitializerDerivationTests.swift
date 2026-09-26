import Testing
@testable import PropertyLawCore

/// A text-literal initializer is passed over: the compiler calls it with source text, and
/// `BigUInt`'s force-unwraps a decimal parse of it, trapping on nearly every drawn scalar.
struct TextLiteralInitializerDerivationTests {

    private func shape(_ initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: "Big", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [], hasUserInit: true, initializers: initializers
        )
    }

    private func emitted(_ shape: TypeShape) -> String {
        GeneratorExpressionEmitter.expression(typeName: shape.name, strategy: DerivationStrategist.strategy(for: shape))
    }

    @Test("a unicode-scalar literal initializer is skipped for a later derivable one")
    func unicodeScalarLiteralIsSkipped() {
        let found = shape([
            InitializerSignature(parameters: [
                InitializerParameter(label: "unicodeScalarLiteral", typeName: "Unicode.Scalar")
            ]),
            InitializerSignature(parameters: [InitializerParameter(label: "value", typeName: "Int")])
        ])
        #expect(emitted(found) == "Gen<Int>.int().map { Big(value: $0) }")
    }

    @Test("string and grapheme-cluster literal initializers are declined; integer literals are kept",
          arguments: ["stringLiteral", "extendedGraphemeClusterLiteral"])
    func textLiteralsAreDeclined(label: String) {
        let text = InitializerSignature(parameters: [InitializerParameter(label: label, typeName: "String")])
        #expect(DerivationStrategist.isDeclined(text, in: shape([text])))
        let integer = InitializerSignature(parameters: [InitializerParameter(label: "integerLiteral", typeName: "Int")])
        #expect(!DerivationStrategist.isDeclined(integer, in: shape([integer])))
    }
}
