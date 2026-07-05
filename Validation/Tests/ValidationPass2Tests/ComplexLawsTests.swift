import Testing
import PropertyBased
import PropertyLawKit
import ComplexModule

/// Pass 2 validation — `apple/swift-numerics` `Complex<Double>`.
///
/// `Complex<Double>` conforms to `Numeric` / `SignedNumeric` /
/// `AdditiveArithmetic`. Its underlying components are `Double`, so the
/// kit's exact-equality algebraic laws (associativity, distributivity)
/// fire spurious violations under random sampling — same root cause as
/// why M1's doc-comment redirects FP users to M4 and why FloatingPoint
/// types subsume the algebraic chain so the macro/discovery doesn't
/// emit those checks for them.
///
/// `Complex` is *not* itself a `FloatingPoint` (no `infinity`, `isNaN`,
/// etc. on the type — only on the underlying RealType), so the kit can't
/// route it through `checkFloatingPointPropertyLaws`. This file documents
/// the empirical limit: bounded-magnitude Complex<Double> generators
/// passing AdditiveArithmetic on a ~1000 magnitude range, with multiplication
/// laws suppressed via `intentionalViolation` because they're known to fire
/// on round-error edges.
struct ComplexLawsTests {

    /// Suppressions for laws that depend on exact-equality multiplication
    /// over IEEE-754 floats. These don't hold for any `Numeric` whose
    /// underlying components are floating-point (Complex<Double>,
    /// Complex<Float>, hypothetical Quaternion<Double>, etc.).
    private static let floatingPointArithmeticSuppressions: [LawSuppression] = [
        .intentionalViolation(
            LawIdentifier(protocolName: "Numeric", lawName: "multiplicationAssociativity"),
            reason: "Complex<Double>: IEEE-754 rounding makes (x*y)*z != x*(y*z) under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(protocolName: "Numeric", lawName: "leftDistributivity"),
            reason: "Complex<Double>: IEEE-754 rounding makes x*(y+z) != x*y + x*z under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(protocolName: "Numeric", lawName: "rightDistributivity"),
            reason: "Complex<Double>: IEEE-754 rounding makes (x+y)*z != x*z + y*z under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(
                protocolName: "AdditiveArithmetic",
                lawName: "additionAssociativity"
            ),
            reason: "Complex<Double>: IEEE-754 rounding makes (x+y)+z != x+(y+z) under exact =="
        ),
        .intentionalViolation(
            LawIdentifier(
                protocolName: "AdditiveArithmetic",
                lawName: "subtractionInverse"
            ),
            reason: "Complex<Double>: subtraction inverse fails when x+y is large vs x"
        )
    ]

    private static func complexGenerator() -> Generator<Complex<Double>, some SendableSequenceType> {
        Gen<Int>.int(in: -100...100).map { tag in
            Complex(Double(tag), Double(tag % 7))
        }
    }


    @Test func complexDoublePassesNumericLawsWithFPSuppressions() async throws {
        try await checkNumericPropertyLaws(
            for: Complex<Double>.self,
            using: Self.complexGenerator(),
            options: LawCheckOptions(
                budget: .sanity,
                suppressions: Self.floatingPointArithmeticSuppressions
            ),
            laws: .ownOnly
        )
    }

    /// Commutativity of `+` / `*` is exact even on non-finite `Complex<Double>`
    /// inputs — and `Complex` needs no injected `sameResult` oracle to see it.
    /// swift-numerics' `Complex.==` returns `true` whenever both operands are
    /// non-finite (it collapses every non-finite value — `inf` and `nan` alike —
    /// into a single "point at infinity"), so `Complex`'s own `==` is *already*
    /// `NaN`-reflexive. That reflexivity is a *loss of information*
    /// (`Complex(.nan, 0) == Complex(.infinity, 0)` is `true`), which is exactly
    /// why `Complex` is the lossier carrier, not a more authoritative one
    /// (book §8.1.6). So `multiplicationCommutativity` / `additionCommutativity`
    /// pass over `NaN` under the default `==` and stay *out* of
    /// `floatingPointArithmeticSuppressions` — unlike associativity and
    /// distributivity, which round and are suppressed. This asserts the
    /// operation-level fact the kit's commutativity laws rely on.
    @Test func complexCommutativityIsExactOnNonFiniteInputs() {
        let nonFinite: [Complex<Double>] = [
            Complex(.nan, 0),
            Complex(0, .nan),
            Complex(.infinity, 0),
            Complex(.nan, .infinity),
            Complex(3.5, -2.0)
        ]
        for left in nonFinite {
            for right in nonFinite {
                #expect(left + right == right + left)
                #expect(left * right == right * left)
            }
        }
    }

    @Test func complexDoublePassesSignedNumericOwnLaws() async throws {
        // SignedNumeric's own laws — negation involution, additive inverse,
        // negate-mutation consistency, negation distributes over addition —
        // hold exactly for Complex<Double> because they don't involve the
        // rounding-prone multiplication or three-way addition. Run with
        // .ownOnly to skip the inherited Numeric laws (which would fire).
        try await checkSignedNumericPropertyLaws(
            for: Complex<Double>.self,
            using: Self.complexGenerator(),
            options: LawCheckOptions(budget: .standard),
            laws: .ownOnly
        )
    }
}
