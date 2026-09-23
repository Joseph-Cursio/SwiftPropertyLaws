import PropertyBased
import Testing
@testable import PropertyLawCore

/// v4.8 — the `String` generators mix the **subject's own** string literals into their alphanumeric
/// baseline. See `RawType.subjectBaseline(_:)` for why, and for the measurement it reproduces.
@Suite("RawType — v4.8 subject-token String generators")
struct SubjectTokenGeneratorTests {

    // MARK: - No tokens: nothing moves

    /// The whole guarantee existing consumers rely on: with no subject tokens, both generators render
    /// exactly what they rendered before, so no golden anywhere moves.
    @Test("with no subject tokens both generators are the unmodified expressions")
    func noTokensIsUnchanged() throws {
        let edge = try #require(RawType.string.edgeBiasedGeneratorExpression(subjectTokens: []))
        let hostile = try #require(RawType.string.hostileGeneratorExpression(subjectTokens: []))
        #expect(edge == RawType.string.edgeBiasedGeneratorExpression)
        #expect(hostile == RawType.string.hostileGeneratorExpression)
        // And the baseline arm is the plain alphanumeric generator, not a mixture.
        #expect(edge.hasPrefix("Gen.frequency((3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), "))
        #expect(hostile.hasPrefix("Gen.frequency((3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), "))
    }

    // MARK: - Tokens: only the baseline arm changes

    @Test("subject tokens join the baseline arm, escaped, and every curated arm is untouched")
    func tokensJoinTheBaselineOnly() throws {
        let plain = try #require(RawType.string.edgeBiasedGeneratorExpression)
        let tokens = ["#", "&amp;", "\"", "\n"]
        let mixed = try #require(RawType.string.edgeBiasedGeneratorExpression(subjectTokens: tokens))
        #expect(mixed.contains(##"["#", "&amp;", "\"", "\n"] as [String]"##))
        // Everything after the baseline arm is byte-identical: the curated tokens keep their weights.
        let curatedArm = "(1.0, Gen<String?>.element(of: [\"\","
        let tail = { (expression: String) in expression.components(separatedBy: curatedArm).last }
        #expect(tail(plain) == tail(mixed))
    }

    @Test("empty and repeated tokens are dropped, and the list is capped")
    func tokensAreCleaned() {
        #expect(RawType.subjectBaseline(["", ""]) == "Gen<Character>.letterOrNumber.string(of: 0...8)")
        let repeated = RawType.subjectBaseline(["#", "#", "", "#"])
        #expect(repeated.components(separatedBy: "\"#\"").count - 1 == 2, "one token, drawn alone and embedded")
        let many = RawType.subjectBaseline((0..<40).map { "t\($0)" })
        #expect(many.contains("\"t15\""))
        #expect(!many.contains("\"t16\""))
    }

    @Test("non-String raw types have no subject-token variant")
    func nonStringIsNil() {
        #expect(RawType.int.edgeBiasedGeneratorExpression(subjectTokens: ["#"]) == nil)
        #expect(RawType.int.hostileGeneratorExpression(subjectTokens: ["#"]) == nil)
    }

    // MARK: - The expression compiles and draws the tokens

    /// The live baseline arm for `subjectTokens: ["#"]`, written exactly as `subjectBaseline` renders
    /// it — **do not simplify it**; the assertion below pins the emitter to this text.
    private static let hashBaseline = Gen.frequency(
        (2.0, Gen<Character>.letterOrNumber.string(of: 0...8)),
        (1.0, Gen<String?>.element(of: ["#"] as [String]).map { $0! }),
        (1.0, zip(
            zip(
                Gen<Character>.letterOrNumber.string(of: 0...4),
                Gen<String?>.element(of: ["#"] as [String]).map { $0! }
            ).map { $0 + $1 },
            Gen<Character>.letterOrNumber.string(of: 0...4)
        ).map { $0 + $1 })
    )

    @Test("the subject arm compiles, draws the token alone and embedded, and matches the emitter")
    func subjectArmRunsAndMatches() {
        var generator: any SeededRandomNumberGenerator =
            Xoshiro(seed: (0xDEAD_BEEF, 0xCAFE_F00D, 0x1234_5678, 0x9ABC_DEF0))
        let draws = (0..<400).map { _ in Self.hashBaseline.run(using: &generator) }
        // The line that hung a real Markdown parser starts with `#`; the generator must produce it.
        #expect(draws.contains("#"))
        #expect(draws.contains { $0.contains("#") && $0 != "#" })
        #expect(draws.contains { !$0.contains("#") }, "the alphanumeric baseline still draws")
        #expect(RawType.subjectBaseline(["#"]) == """
        Gen.frequency((2.0, Gen<Character>.letterOrNumber.string(of: 0...8)), \
        (1.0, Gen<String?>.element(of: ["#"] as [String]).map { $0! }), \
        (1.0, zip(zip(Gen<Character>.letterOrNumber.string(of: 0...4), \
        Gen<String?>.element(of: ["#"] as [String]).map { $0! }).map { $0 + $1 }, \
        Gen<Character>.letterOrNumber.string(of: 0...4)).map { $0 + $1 }))
        """)
    }
}
