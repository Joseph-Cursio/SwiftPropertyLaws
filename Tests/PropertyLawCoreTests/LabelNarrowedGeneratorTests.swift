import Testing
@testable import PropertyLawCore

/// **A parameter label can declare a domain the type does not.**
///
/// Derivation resolved every initializer parameter by type alone. swift-system declares
/// `internal init(ascii: Unicode.Scalar)` (`SystemString.swift:27`), which traps on anything
/// outside ASCII, and the emitted generator was
///
///     Gen<Unicode.Scalar>.unicodeScalar().map { SystemChar(ascii: $0) }
///
/// `unicodeScalar()` draws ASCII about 4 times in 10 by design, so this is not a tail risk —
/// it fires within a couple of trials, every run. Measured 2026-08-21 on `swift-system` @
/// `6a63f08`: **9 of the 19 laws that reached the build stage compiled, linked, ran and died**
/// on `Fatal error: Code point value does not fit into ASCII`, the largest single bucket in
/// that survey.
///
/// The arms below are mostly **controls**, and deliberately so. The rule is one line and the
/// risk is not that it fails to fire — it is that it fires somewhere it should not, quietly
/// shrinking a domain nobody asked to shrink.
struct LabelNarrowedGeneratorTests {

    private func shape(_ name: String, _ parameters: [InitializerParameter]) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [],
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: parameters)]
        )
    }

    private func emitted(_ shape: TypeShape) -> String {
        GeneratorExpressionEmitter.expression(
            typeName: shape.name,
            strategy: DerivationStrategist.strategy(for: shape)
        )
    }

    @Test("an `ascii:` scalar parameter narrows to the ASCII generator")
    func asciiScalarNarrows() {
        let source = emitted(
            shape("SystemChar", [InitializerParameter(label: "ascii", typeName: "Unicode.Scalar")])
        )
        #expect(source == "Gen<Unicode.Scalar>.asciiScalar().map { SystemChar(ascii: $0) }")
    }

    @Test("the `UnicodeScalar` spelling narrows too")
    func theOtherSpellingNarrows() {
        let source = emitted(
            shape("SystemChar", [InitializerParameter(label: "ascii", typeName: "UnicodeScalar")])
        )
        #expect(source.contains("Gen<Unicode.Scalar>.asciiScalar()"))
    }

    /// **The control that matters most.** A scalar parameter with any other label must keep
    /// the full-domain generator: `unicodeScalar()` exists because text-handling code should
    /// be tested across the seams where byte assumptions break, and narrowing it by default
    /// would quietly delete that coverage everywhere.
    @Test("a scalar parameter with any other label keeps the full domain")
    func anUnlabelledScalarIsUnchanged() {
        for label in ["scalar", "value", "character", "first", nil] {
            let source = emitted(
                shape("Wrapper", [InitializerParameter(label: label, typeName: "Unicode.Scalar")])
            )
            #expect(
                source.contains("Gen<Unicode.Scalar>.unicodeScalar()"),
                "label \(label ?? "nil") must not narrow"
            )
            #expect(!source.contains("asciiScalar"))
        }
    }

    /// The label is not narrowing evidence on its own — it only means something beside a type
    /// whose ASCII subset is defined. `ascii: Int` has no such subset and must be left alone.
    @Test("the `ascii:` label alone narrows nothing")
    func theLabelAloneIsNotEnough() {
        for typeName in ["Int", "String", "UInt8", "Character"] {
            let source = emitted(
                shape("Wrapper", [InitializerParameter(label: "ascii", typeName: typeName)])
            )
            #expect(!source.contains("asciiScalar"), "\(typeName) must not narrow")
        }
    }

    /// Narrowing applies per parameter, not per initializer.
    @Test("only the ascii parameter narrows in a mixed initializer")
    func narrowingIsPerParameter() {
        let source = emitted(
            shape("Pair", [
                InitializerParameter(label: "ascii", typeName: "Unicode.Scalar"),
                InitializerParameter(label: "other", typeName: "Unicode.Scalar")
            ])
        )
        #expect(source.contains("Gen<Unicode.Scalar>.asciiScalar()"))
        #expect(source.contains("Gen<Unicode.Scalar>.unicodeScalar()"))
    }

    /// The identity arm. Every derivation that does not match a rule must emit byte-identical
    /// text to what it emitted before this existed — the claim the doc comment makes, asserted
    /// rather than trusted.
    @Test("an unrelated derivation is byte-identical")
    func unrelatedDerivationsAreUnchanged() {
        let source = emitted(
            shape("User", [
                InitializerParameter(label: "name", typeName: "String"),
                InitializerParameter(label: "count", typeName: "Int")
            ])
        )
        #expect(source == """
            zip(Gen<Character>.letterOrNumber.string(of: 0...8), Gen<Int>.int())
                        .map { User(name: $0.0, count: $0.1) }
            """)
    }
}
