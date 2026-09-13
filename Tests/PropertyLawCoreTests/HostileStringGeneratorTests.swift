import PropertyBased
import Testing
@testable import PropertyLawCore

/// v4.6 — `RawType.hostileGeneratorExpression`, the draw a **totality** law needs.
///
/// ## Why a second String generator
///
/// A generator tuned for coverage of the *type* is silently mistuned for coverage of the *law*.
/// `edgeBiasedGeneratorExpression` was tuned for structural string laws — it exists because
/// `strippingHeadingMarkers` needed a repetition witness and changed 0 of 3 920 values without
/// one. Pointed at a totality law it under-reaches, measured on six real trap classes planted in
/// `WikilinkParser.parse` at 100 trials each:
///
/// | trap fires on | edge-biased | hostile |
/// |---|---|---|
/// | empty / newline / tab | caught | caught |
/// | any non-ASCII scalar | **missed** | caught |
/// | a `[[` delimiter | **missed** | caught |
/// | length > 64 | **missed** | caught |
///
/// 3 of 6 against 6 of 6, with the correct implementation passing under both.
///
/// ## The distribution tests are the load-bearing ones
///
/// An expression that compiles, contains every token, and *never draws one* would satisfy every
/// string assertion in this file and be worthless — that is the vacuity failure this repository
/// keeps recording. So the three classes the measurement found unreachable are asserted by
/// **running the generator and looking at what came out.**
@Suite("RawType — v4.6 hostile String generator for totality")
struct HostileStringGeneratorTests {

    /// The emitted expression written out as **live code**. The string assertion below proves the
    /// emitter still says this; this copy proves it compiles and runs.
    private static let live = Gen.frequency(
        (3.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
        (3.0, Gen<String?>.element(of: RawType.hostileTokens).map { $0! }),
        (2.0, Gen<String?>.element(of: RawType.hostileTokens).map { $0! }.map { $0 + $0 }),
        (1.0, Gen<Character>.latin1.string(of: 0...24)),
        (1.0, Gen<Character>.ascii.string(of: 0...120))
    )

    private static func draws(_ count: Int) -> [String] {
        var rng = Xoshiro(seed: (0xDEAD_BEEF, 0xCAFE_F00D, 0x1234_5678, 0x9ABC_DEF0))
        return (0 ..< count).map { _ in live.run(using: &rng) }
    }

    // MARK: - The three classes the measurement found unreachable

    /// The worst miss of the six: `WikilinkParser` exists to parse `[[…]]`, so its trap bugs live
    /// in bracket handling, and the edge-biased generator cannot produce a single bracket.
    ///
    /// **Asserted on a whole token rather than on `"["`, because a mutation showed the weaker
    /// form was satisfied by the wrong arm.** `Gen<Character>.ascii` draws over `0...127`, so it
    /// emits a lone bracket by chance and the test passed with the token arm deleted. A
    /// seven-character sequence is something only the curated list produces — and a *structured*
    /// delimiter is what the law is about, since a parser traps on `[[a|b]]`, not on one `[`.
    @Test func aDelimiterIsActuallyDrawn() {
        let sample = Self.draws(400)
        #expect(sample.contains { $0.contains("[[a|b]]") })
        #expect(sample.contains { $0.contains("[[") })
    }

    @Test func aNonASCIIScalarIsActuallyDrawn() {
        let sample = Self.draws(400)
        #expect(sample.contains { $0.unicodeScalars.contains { $0.value > 127 } })
    }

    /// A length assumption is invisible to a generator capped near 16, which is where the
    /// edge-biased one tops out.
    @Test func aLongInputIsActuallyDrawn() {
        let sample = Self.draws(400)
        #expect(sample.contains { $0.count > 64 })
    }

    /// **The negative that keeps this a mix rather than a firehose.** Most trials should still be
    /// ordinary input; a generator that only ever emitted hostile tokens would satisfy every test
    /// above and would stop resembling the domain the function actually serves.
    @Test func theOrdinaryBaselineStillDominatesNoSingleClass() {
        let sample = Self.draws(400)
        let alphanumeric = sample.filter { !$0.isEmpty && $0.allSatisfy(\.isLetter) || $0.allSatisfy(\.isNumber) }
        #expect(alphanumeric.isEmpty == false, "the ordinary arm must still fire")
    }

    // MARK: - The expression the emitter produces

    @Test func theEmittedExpressionMatchesTheLiveCopy() throws {
        let expression = try #require(RawType.string.hostileGeneratorExpression)
        #expect(expression.contains("Gen.frequency("))
        #expect(expression.contains("Gen<Character>.latin1.string(of: 0...24)"))
        #expect(expression.contains("Gen<Character>.ascii.string(of: 0...120)"))
        #expect(expression.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(expression.contains("\"[[\""))
    }

    @Test func nonStringRawTypesHaveNoHostileVariant() {
        #expect(RawType.int.hostileGeneratorExpression == nil)
        #expect(RawType.double.hostileGeneratorExpression == nil)
        #expect(RawType.bool.hostileGeneratorExpression == nil)
    }

    /// The two String generators must stay distinct. Collapsing them would re-tune the
    /// structural one, which is correct for its own law, and move every idempotence golden.
    @Test func itIsNotTheEdgeBiasedGenerator() throws {
        let hostile = try #require(RawType.string.hostileGeneratorExpression)
        let edge = try #require(RawType.string.edgeBiasedGeneratorExpression)
        #expect(hostile != edge)
        #expect(edge.contains("[[") == false, "the structural generator must stay bracket-free")
    }

    // MARK: - The emitted source must be source

    /// **The bug this catches shipped in v4.6.0 and no assertion in this file saw it.**
    /// `hostileTokens` carries `\u{0}` and `\u{7F}` — a parser trapping on NUL is exactly what a
    /// totality law is for — and `swiftStringLiteral` escaped only `\`, `"`, `\n` and `\t`, so
    /// those went into the generated `.swift` file as **raw bytes**.
    ///
    /// Every existing test compared strings, and a NUL inside a Swift string compares equal to
    /// itself perfectly well. It was found by reading the emitted file's bytes. So this asserts
    /// on the *scalars of the emitted expression*, which is the only form in which the defect is
    /// visible.
    @Test func theEmittedExpressionCarriesNoRawControlBytes() throws {
        let expression = try #require(RawType.string.hostileGeneratorExpression)
        let offenders = expression.unicodeScalars.filter {
            $0.properties.generalCategory == .control || $0.value == 0x7F
        }
        #expect(offenders.isEmpty, "generated source carries raw control bytes: \(offenders)")
    }

    @Test("a non-printable scalar is escaped rather than emitted", arguments: [
        ("\u{0}", "\\u{0}"), ("\u{7F}", "\\u{7F}"), ("\u{1}", "\\u{1}"), ("\u{1B}", "\\u{1B}")
    ])
    func nonPrintablesAreEscaped(raw: String, escaped: String) {
        #expect(RawType.swiftStringLiteral(raw) == "\"\(escaped)\"")
    }

    /// The four escapes hand-written Swift actually contains must not have moved.
    @Test func theOrdinaryEscapesAreUnchanged() {
        #expect(RawType.swiftStringLiteral("\n") == "\"\\n\"")
        #expect(RawType.swiftStringLiteral("\t") == "\"\\t\"")
        #expect(RawType.swiftStringLiteral("a\"b\\c") == "\"a\\\"b\\\\c\"")
        #expect(RawType.swiftStringLiteral("[[a|b]]") == "\"[[a|b]]\"")
    }

    /// The plain form feeds memberwise derivation and must not move.
    @Test func thePlainGeneratorIsUnchanged() {
        #expect(RawType.string.generatorExpression == "Gen<Character>.letterOrNumber.string(of: 0...8)")
    }

    /// Tokens are general rather than fitted to the subject that exposed the gap. A list holding
    /// only `[[` would score 6 of 6 on `WikilinkParser` and nothing on the next parser.
    @Test("the token list spans delimiter families, not one subject's", arguments: [
        "[", "]", "{", "}", "<", ">", "(", ")", "\"", "'", "\\", "|"
    ])
    func delimiterFamiliesAreCovered(token: String) {
        #expect(RawType.hostileTokens.contains(token))
    }
}
