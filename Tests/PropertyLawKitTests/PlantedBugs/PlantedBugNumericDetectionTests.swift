import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate — v1.4 numeric cluster (M1 share).
/// Each test plants a violation against one of the cluster's Strict-tier
/// laws and asserts the framework's detection.
struct PlantedBugNumericDetectionTests {

    // MARK: - AdditiveArithmetic Strict-tier planted bugs

    @Test func detectsBadZeroIdentity() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkAdditiveArithmeticPropertyLaws(
                for: BadZeroIdentity.self,
                using: Gen<BadZeroIdentity>.badZeroIdentity(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("AdditiveArithmetic.zeroAdditiveIdentity"),
            "expected zeroAdditiveIdentity in violation set; got: \(laws)"
        )
    }

    @Test func detectsNonAssociativeAddition() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkAdditiveArithmeticPropertyLaws(
                for: NonAssociativeAddition.self,
                using: Gen<NonAssociativeAddition>.nonAssociativeAddition(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("AdditiveArithmetic.additionAssociativity"),
            "expected additionAssociativity in violation set; got: \(laws)"
        )
    }

    // MARK: - Numeric Strict-tier planted bugs

    @Test func detectsNonCommutativeMultiply() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkNumericPropertyLaws(
                for: NonCommutativeMultiply.self,
                using: Gen<NonCommutativeMultiply>.nonCommutativeMultiply(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Numeric.multiplicationCommutativity"),
            "expected multiplicationCommutativity in violation set; got: \(laws)"
        )
    }

    @Test func detectsBrokenOneIdentity() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkNumericPropertyLaws(
                for: BrokenOneIdentity.self,
                using: Gen<BrokenOneIdentity>.brokenOneIdentity(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Numeric.oneMultiplicativeIdentity"),
            "expected oneMultiplicativeIdentity in violation set; got: \(laws)"
        )
    }

    // MARK: - SignedNumeric Strict-tier planted bugs

    @Test func detectsBrokenNegationOffByOne() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSignedNumericPropertyLaws(
                for: BrokenNegationOffByOne.self,
                using: Gen<BrokenNegationOffByOne>.brokenNegationOffByOne(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SignedNumeric.negationInvolution")
                || laws.contains("SignedNumeric.additiveInverse"),
            "expected a SignedNumeric involution / inverse violation; got: \(laws)"
        )
    }

    /// Affine negation survives involution but breaks distribution — drives
    /// the `negationDistributesOverAddition` counterexample path.
    @Test func detectsAffineNegationDistributionBreak() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSignedNumericPropertyLaws(
                for: AffineNegation.self,
                using: Gen<AffineNegation>.affineNegation(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SignedNumeric.negationDistributesOverAddition"),
            "expected negationDistributesOverAddition in violation set; got: \(laws)"
        )
    }

    /// A no-op `negate()` diverges from `prefix -` — drives the
    /// `negateMutationConsistency` counterexample path.
    @Test func detectsNoOpNegateMutationBreak() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSignedNumericPropertyLaws(
                for: NoOpNegate.self,
                using: Gen<NoOpNegate>.noOpNegate(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SignedNumeric.negateMutationConsistency"),
            "expected negateMutationConsistency in violation set; got: \(laws)"
        )
    }
}
