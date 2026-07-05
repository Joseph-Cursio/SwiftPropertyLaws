import Testing
import PropertyBased
@testable import PropertyLawKit

/// Tests for the `NaN`-reflexive `sameResult` oracle (book §8.1.4–8.1.7 slice).
///
/// The kit runs exactly *commutativity* of `+` / `*` over floats — the only
/// algebraic laws that hold bit-for-bit modulo `NaN` — using `floatSameResult`.
/// Associativity / distributivity / subtraction-inverse stay excluded (they
/// fail by unbounded amounts under cancellation, so no oracle rescues them).
struct SameResultTests {

    @Test func floatSameResultIsNaNReflexive() {
        #expect(floatSameResult(Double.nan, Double.nan) == true)
        #expect(floatSameResult(Float.nan, Float.nan) == true)
    }

    @Test func floatSameResultFallsBackToExactEqualityOffNaN() {
        #expect(floatSameResult(1.0, 1.0) == true)
        #expect(floatSameResult(1.0, 2.0) == false)
        #expect(floatSameResult(Double.infinity, Double.infinity) == true)
        #expect(floatSameResult(-0.0, 0.0) == true) // IEEE-754 signed-zero equality
    }

    /// The oracle must not over-collapse: a `NaN` against a non-`NaN` (and the
    /// two *distinct* non-finite values `inf` vs `nan`) are not the same result.
    /// This is what keeps a genuinely asymmetric operation detectable.
    @Test func floatSameResultDoesNotMaskGenuineAsymmetry() {
        #expect(floatSameResult(Double.nan, 1.0) == false)
        #expect(floatSameResult(1.0, Double.nan) == false)
        #expect(floatSameResult(Double.infinity, Double.nan) == false)
    }

    /// §8.1.5's self-correcting property. The C-style `min` (`b < a ? b : a`)
    /// is genuinely asymmetric on `NaN` because every `<` involving `NaN` is
    /// false: `min(NaN, 1) == NaN` but `min(1, NaN) == 1`. The oracle still
    /// reports the two sides as different — it fixes the `NaN`-vs-`NaN` artifact
    /// without hiding real asymmetry.
    @Test func asymmetricOperationStillFailsUnderTheOracle() {
        func cMin(_ lhs: Double, _ rhs: Double) -> Double { rhs < lhs ? rhs : lhs }
        let forward = cMin(Double.nan, 1.0)  // NaN  (1 < NaN is false → lhs)
        let reversed = cMin(1.0, Double.nan) // 1.0  (NaN < 1 is false → lhs)
        #expect(floatSameResult(forward, reversed) == false)
    }

    /// Commutativity of `+` / `*` over a `NaN`-inclusive `Double` generator
    /// passes: every `NaN`-on-both-sides case is absorbed by the reflexive
    /// oracle, and the operations are otherwise bit-for-bit symmetric.
    @Test func floatCommutativityPassesOverNaNGenerator() async throws {
        let results = try await checkFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.doubleWithNaN(),
            options: LawCheckOptions(budget: .standard)
        )
        let commutativity = results.filter {
            $0.protocolLaw == "FloatingPoint.additionCommutativity"
                || $0.protocolLaw == "FloatingPoint.multiplicationCommutativity"
        }
        #expect(commutativity.count == 2)
        #expect(commutativity.allSatisfy { $0.isViolation == false })
    }
}
