import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate — v1.4 floating-point cluster (M4 + M5).
///
/// `BrokenFloat` is a single `Double`-wrapping `BinaryFloatingPoint` conformer
/// carrying one scoped plant per law, so these two tests drive every
/// FloatingPoint and BinaryFloatingPoint counterexample-formatting path.
struct PlantedBugFloatingPointDetectionTests {

    // MARK: - FloatingPoint (9 always-on + 5 NaN-domain)

    @Test func brokenFloatViolatesAllFloatingPointArms() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            // allowNaN: true so the five NaN-domain laws run too.
            try await checkFloatingPointPropertyLaws(
                for: BrokenFloat.self,
                using: Gen<BrokenFloat>.brokenFloat(),
                options: LawCheckOptions(budget: .sanity, allowNaN: true)
            )
        }
        let laws = Set(violation?.results.filter(\.isViolation).map(\.protocolLaw) ?? [])
        let expected: Set = [
            "FloatingPoint.infinityIsInfinite",
            "FloatingPoint.negativeInfinityComparison",
            "FloatingPoint.zeroIsZero",
            "FloatingPoint.signedZeroEquality",
            "FloatingPoint.roundedZeroIdentity",
            "FloatingPoint.additiveInverseFinite",
            "FloatingPoint.nextUpDownRoundTrip",
            "FloatingPoint.signMatchesIsLessThanZero",
            "FloatingPoint.absoluteValueNonNegative",
            "FloatingPoint.nanIsNaN",
            "FloatingPoint.nanInequality",
            "FloatingPoint.nanPropagatesAddition",
            "FloatingPoint.nanPropagatesMultiplication",
            "FloatingPoint.nanComparisonIsUnordered"
        ]
        #expect(
            expected.isSubset(of: laws),
            "missing arms: \(expected.subtracting(laws).sorted())"
        )
    }

    // MARK: - BinaryFloatingPoint (4 own laws)

    @Test func brokenFloatViolatesAllBinaryFloatingPointArms() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkBinaryFloatingPointPropertyLaws(
                for: BrokenFloat.self,
                using: Gen<BrokenFloat>.brokenFloat(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = Set(violation?.results.filter(\.isViolation).map(\.protocolLaw) ?? [])
        let expected: Set = [
            "BinaryFloatingPoint.radix2Constraint",
            "BinaryFloatingPoint.significandExponentReconstruction",
            "BinaryFloatingPoint.binadeMembership",
            "BinaryFloatingPoint.convertingFromIntegerExactness"
        ]
        #expect(
            expected.isSubset(of: laws),
            "missing arms: \(expected.subtracting(laws).sorted())"
        )
    }
}
