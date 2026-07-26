import Testing
@testable import PropertyLawCore

/// Direct `#expect` pins on the rendered generator expression. Single
/// source of truth for the strategy → Swift-source mapping consumed by
/// the macro (`PropertyLawSuiteMacro`), the discovery plugin
/// (`GeneratedFileEmitter`), and downstream consumers like
/// SwiftInferProperties M5's lifted-test stub writeout (the K-prep-M1
/// promotion target).
@Suite("GeneratorExpressionEmitter — DerivationStrategy → Swift source (K-prep-M1)")
struct GeneratorExpressionEmitterTests {

    @Test func userGenStrategyEmitsTypeNameDotGen() {
        let expr = GeneratorExpressionEmitter.expression(
            typeName: "Widget",
            strategy: .userGen
        )
        #expect(expr == "Widget.gen()")
    }

    @Test func todoStrategyAlsoEmitsTypeNameDotGen() {
        // `.todo` shares the `<TypeName>.gen()` shape so the user gets a
        // compile error pointing at the missing `gen()` symbol — the
        // macro's diagnostic surfaces the why-it's-todo context.
        let expr = GeneratorExpressionEmitter.expression(
            typeName: "Mystery",
            strategy: .todo(reason: "no recognized strategy")
        )
        #expect(expr == "Mystery.gen()")
    }

    /// Until now this pinned `"Gen<Side>.element(of: Side.allCases)"` — byte-exact,
    /// green for the whole life of the arm, and describing an expression that
    /// **could never compile**: `Gen.element(of:)` is declared
    /// `where Value == C.Element?`, so `Gen<Side>` asks the compiler to prove
    /// `Side == Side?`. A codegen test that compares text to text can have both
    /// sides wrong together, and here it did.
    ///
    /// The executable counterpart lives in `EmittedExpressionCompilesTests`,
    /// which writes this expression out as live code and runs it. Keep both:
    /// this one is the readable record of what is emitted, that one is the proof
    /// that what is emitted is Swift.
    @Test func caseIterableStrategyEmitsElementOfAllCases() {
        let expr = GeneratorExpressionEmitter.expression(
            typeName: "Side",
            strategy: .caseIterable
        )
        #expect(expr == "Gen<Side?>.element(of: Side.allCases).compactMap { $0 }")
    }

    @Test func memberwiseArbitraryDelegatesToMemberwiseEmitter() {
        // The memberwise-Arbitrary arm is a thin re-export of
        // `MemberwiseEmitter.expression` — verify byte-equality between
        // the two paths so a future divergence in the memberwise emitter
        // can't desync this surface.
        let members = [
            MemberSpec(name: "amount", rawType: .int),
            MemberSpec(name: "currency", rawType: .string)
        ]
        let viaUnified = GeneratorExpressionEmitter.expression(
            typeName: "Money",
            strategy: .memberwiseArbitrary(members: members)
        )
        let viaMemberwise = MemberwiseEmitter.expression(typeName: "Money", members: members)
        #expect(viaUnified == viaMemberwise)
    }

    @Test func rawRepresentableStringEnumLiftsViaCompactMapOnNewLine() {
        // The `.rawRepresentable` arm intentionally emits `.compactMap`
        // on a fresh line so even types with long names + long raw-type
        // generators (here `String`'s 8-char letter-or-number generator)
        // stay within reasonable line widths. K-prep-M1 canonicalised
        // on this multi-line shape — the discovery tool previously
        // emitted a single-line version of the same expression.
        let expr = GeneratorExpressionEmitter.expression(
            typeName: "Direction",
            strategy: .rawRepresentable(.string)
        )
        let expected = """
            Gen<Character>.letterOrNumber.string(of: 0...8)
                        .compactMap { Direction(rawValue: $0) }
            """
        #expect(expr == expected)
    }

    @Test func rawRepresentableIntEnumUsesIntGenerator() {
        let expr = GeneratorExpressionEmitter.expression(
            typeName: "Code",
            strategy: .rawRepresentable(.int)
        )
        let expected = """
            Gen<Int>.int()
                        .compactMap { Code(rawValue: $0) }
            """
        #expect(expr == expected)
    }
}
