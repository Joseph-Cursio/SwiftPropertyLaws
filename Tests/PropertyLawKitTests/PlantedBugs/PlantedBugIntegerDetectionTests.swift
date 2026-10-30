import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate — v1.4 numeric cluster (M2 share).
struct PlantedBugIntegerDetectionTests {

    // MARK: - BinaryInteger Strict-tier planted bug

    @Test func detectsBrokenBitwiseNegation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkBinaryIntegerPropertyLaws(
                for: BrokenBitwiseNegation.self,
                using: Gen<BrokenBitwiseNegation>.brokenBitwiseNegation(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("BinaryInteger.bitwiseDoubleNegation"),
            "expected bitwiseDoubleNegation in violation set; got: \(laws)"
        )
    }

    // MARK: - SignedInteger Strict-tier planted bug

    @Test func detectsLyingSignum() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSignedIntegerPropertyLaws(
                for: LyingSignum.self,
                using: Gen<LyingSignum>.lyingSignum(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SignedInteger.signednessConsistency"),
            "expected signednessConsistency in violation set; got: \(laws)"
        )
    }

    // MARK: - UnsignedInteger Strict-tier planted bug

    @Test func detectsLyingMagnitude() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkUnsignedIntegerPropertyLaws(
                for: LyingMagnitude.self,
                using: Gen<LyingMagnitude>.lyingMagnitude(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("UnsignedInteger.magnitudeIsSelf"),
            "expected magnitudeIsSelf in violation set; got: \(laws)"
        )
    }

    /// `nonNegative` is falsifiable (not tautological): `>=` derives from `<`,
    /// and `NegativeClaimingUnsigned` lies in `<` so `x >= 0` is false. Only
    /// `nonNegative` trips — `magnitude` and `==` stay honest.
    @Test func detectsNegativeClaimingUnsigned() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkUnsignedIntegerPropertyLaws(
                for: NegativeClaimingUnsigned.self,
                using: Gen<NegativeClaimingUnsigned>.negativeClaimingUnsigned(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("UnsignedInteger.nonNegative"),
            "expected nonNegative in violation set; got: \(laws)"
        )
    }

    // MARK: - FixedWidthInteger Strict-tier planted bug

    @Test func detectsBrokenByteSwapped() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkFixedWidthIntegerPropertyLaws(
                for: BrokenByteSwapped.self,
                using: Gen<BrokenByteSwapped>.brokenByteSwapped(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("FixedWidthInteger.byteSwappedInvolution"),
            "expected byteSwappedInvolution in violation set; got: \(laws)"
        )
    }

    // MARK: - Per-arm coverage: BinaryInteger

    /// `ChaoticInteger` breaks every BinaryInteger Strict law except
    /// `bitwiseDoubleNegation`, so a single run exercises all 15 of the
    /// remaining laws' counterexample-formatting paths.
    @Test func chaoticIntegerViolatesAllBinaryIntegerArms() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkBinaryIntegerPropertyLaws(
                for: ChaoticInteger.self,
                using: Gen<ChaoticInteger>.chaoticInteger(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = Set(violation?.results.filter(\.isViolation).map(\.protocolLaw) ?? [])
        let expected: Set = [
            "BinaryInteger.divisionMultiplicationRoundTrip",
            "BinaryInteger.remainderMagnitudeBound",
            "BinaryInteger.selfDivisionIsOne",
            "BinaryInteger.divisionByOneIdentity",
            "BinaryInteger.quotientAndRemainderConsistency",
            "BinaryInteger.bitwiseAndIdempotence",
            "BinaryInteger.bitwiseOrIdempotence",
            "BinaryInteger.bitwiseAndCommutativity",
            "BinaryInteger.bitwiseOrCommutativity",
            "BinaryInteger.bitwiseXorSelfIsZero",
            "BinaryInteger.bitwiseXorZeroIdentity",
            "BinaryInteger.bitwiseAndDistributesOverOr",
            "BinaryInteger.bitwiseDeMorgan",
            "BinaryInteger.shiftByZeroIdentity",
            "BinaryInteger.trailingZeroBitCountRange"
        ]
        #expect(
            expected.isSubset(of: laws),
            "missing arms: \(expected.subtracting(laws).sorted())"
        )
    }

    // MARK: - Per-arm coverage: FixedWidthInteger

    /// `ChaoticFixedWidth` breaks all eight FixedWidthInteger arms that a
    /// conformer can violate. The three `reportingOverflow` consistency laws
    /// and `wrappingArithmeticDoesNotTrap` were originally tautological — they
    /// have since been strengthened to checks independent of the masking
    /// operators (additive/multiplicative identities, round-trips, and the
    /// wrap-around boundary), so the off-by-one plants now trip them.
    /// `byteSwappedInvolution` is the only own law not asserted here — it is
    /// covered by `BrokenByteSwapped`.
    @Test func chaoticFixedWidthViolatesRemainingArms() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkFixedWidthIntegerPropertyLaws(
                for: ChaoticFixedWidth.self,
                using: Gen<ChaoticFixedWidth>.chaoticFixedWidth(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = Set(violation?.results.filter(\.isViolation).map(\.protocolLaw) ?? [])
        let expected: Set = [
            "FixedWidthInteger.bitWidthMatchesType",
            "FixedWidthInteger.addingReportingOverflowConsistency",
            "FixedWidthInteger.subtractingReportingOverflowConsistency",
            "FixedWidthInteger.multipliedReportingOverflowConsistency",
            "FixedWidthInteger.dividedReportingOverflowOnDivByZero",
            "FixedWidthInteger.wrappingArithmeticDoesNotTrap",
            "FixedWidthInteger.minMaxBoundsAreReachable",
            "FixedWidthInteger.nonzeroBitCountRange"
        ]
        #expect(
            expected.isSubset(of: laws),
            "missing arms: \(expected.subtracting(laws).sorted())"
        )
    }

    // MARK: - One fault at a time

    private func violatedLaws<Fault: IntegerFault>(
        _ fault: Fault.Type,
        binaryInteger: Bool = false
    ) async -> Set<String> {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            if binaryInteger {
                try await checkBinaryIntegerPropertyLaws(
                    using: singleFaultIntegers(fault), options: LawCheckOptions(budget: .sanity), laws: .ownOnly)
            } else {
                try await checkFixedWidthIntegerPropertyLaws(
                    using: singleFaultIntegers(fault), options: LawCheckOptions(budget: .sanity), laws: .ownOnly)
            }
        }
        return Set(violation?.results.map(\.protocolLaw) ?? [])
    }

    /// `ChaoticFixedWidth` breaks every check in these laws, so it cannot show
    /// that each check is needed. Each of these faults breaks one check and
    /// leaves the rest of its law true.
    @Test func eachReportingOverflowCheckIsNeededOnItsOwn() async {
        #expect(await violatedLaws(AddingZeroOverflows.self)
            == ["FixedWidthInteger.addingReportingOverflowConsistency"])
        #expect(await violatedLaws(SubtractingZeroOverflows.self)
            == ["FixedWidthInteger.subtractingReportingOverflowConsistency"])
        #expect(await violatedLaws(MultiplyingByOneOverflows.self)
            == ["FixedWidthInteger.multipliedReportingOverflowConsistency"])
    }

    /// `max &+ 1 == min` holds and `min &- 1 == min`. The wrapping law has to
    /// check both boundaries.
    @Test func eachWrapAroundBoundaryIsChecked() async {
        #expect(await violatedLaws(MinMinusOneSaturates.self)
            == ["FixedWidthInteger.wrappingArithmeticDoesNotTrap"])
    }

    /// The quotient is right and the remainder is not.
    @Test func quotientAndRemainderAreCheckedSeparately() async {
        #expect(await violatedLaws(RemainderOffByOne.self, binaryInteger: true)
            == ["BinaryInteger.quotientAndRemainderConsistency"])
    }
}
