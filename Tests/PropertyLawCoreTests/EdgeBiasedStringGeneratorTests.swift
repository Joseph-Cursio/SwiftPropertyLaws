import Testing
@testable import PropertyLawCore

// v3.2 — `RawType.edgeBiasedGeneratorExpression`: an additive edge-biased
// String generator that mixes the alphanumeric baseline with curated
// structural edges so string-structural counterexamples are reachable.
// `generatorExpression` (the plain form, used by memberwise derivation) is
// intentionally unchanged.
@Suite("RawType — v3.2 edge-biased String generator")
struct EdgeBiasedStringGeneratorTests {

    @Test("String exposes an edge-biased generator mixing baseline + structural edges")
    func stringIsEdgeBiased() throws {
        let expression = try #require(RawType.string.edgeBiasedGeneratorExpression)
        // Keeps the plain alphanumeric arm as the majority (weight 3 vs 2)…
        #expect(expression.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(expression.contains("Gen.frequency("))
        // …and injects the structural markers that falsify string logic.
        #expect(expression.contains("\"-\""))
        #expect(expression.contains("\"- \""))
        #expect(expression.contains("\"\\n\""))
    }

    @Test("non-String raw types have no edge-biased variant")
    func nonStringIsNil() {
        #expect(RawType.int.edgeBiasedGeneratorExpression == nil)
        #expect(RawType.double.edgeBiasedGeneratorExpression == nil)
        #expect(RawType.bool.edgeBiasedGeneratorExpression == nil)
    }

    @Test("the plain generatorExpression for String is unchanged (memberwise safety)")
    func plainStringUnchanged() {
        #expect(RawType.string.generatorExpression == "Gen<Character>.letterOrNumber.string(of: 0...8)")
    }

    @Test("swiftStringLiteral escapes quotes, backslashes, newlines, and tabs")
    func literalEscaping() {
        #expect(RawType.swiftStringLiteral("-") == "\"-\"")
        #expect(RawType.swiftStringLiteral("") == "\"\"")
        #expect(RawType.swiftStringLiteral("\n") == "\"\\n\"")
        #expect(RawType.swiftStringLiteral("a\"b\\c") == "\"a\\\"b\\\\c\"")
    }
}
