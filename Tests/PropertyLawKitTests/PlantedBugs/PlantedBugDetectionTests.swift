import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate, relational half. Each test plants a
/// violation and asserts the framework catches it. If any of these regress
/// green-on-buggy, the framework has lost the ability to detect that class of
/// violation and shouldn't be released.
///
/// The gate accumulates one detection test per Strict-tier law across every
/// protocol the kit covers, so it outgrows a single file as new protocols
/// ship. This half holds the protocols whose laws constrain how two values
/// *compare* — Equatable, Hashable, Comparable. The round-trip protocols moved
/// to `PlantedBugRoundTripDetectionTests` when the file passed SwiftLint's
/// 400-line ceiling; add new families as siblings rather than growing either.
struct PlantedBugDetectionTests {

    // MARK: - Equatable Strict-tier planted bugs

    @Test func detectsAntiReflexiveEquality() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkEquatablePropertyLaws(
                for: AntiReflexiveEquatable.self,
                using: Gen<AntiReflexiveEquatable>.antiReflexive(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    @Test func detectsAsymmetricEquality() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkEquatablePropertyLaws(
                for: PriorityCompareEquatable.self,
                using: Gen<PriorityCompareEquatable>.priorityCompare(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains { $0.hasPrefix("Equatable.") },
            "expected an Equatable law violation; got: \(laws)"
        )
    }

    @Test func detectsSymmetryOnlyEquality() async throws {
        // Isolates the symmetry arm. SymmetryOnlyEquatable (`>=`) breaks symmetry
        // and nothing else — reflexive, transitive, negation-consistent — so this
        // is the one Equatable detection test that would go green-on-buggy if the
        // symmetry law were ever blinded. Asserts the *specific* law, not merely
        // "some Equatable law."
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkEquatablePropertyLaws(
                for: SymmetryOnlyEquatable.self,
                using: Gen<SymmetryOnlyEquatable>.symmetryOnly(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Equatable.symmetry"),
            "expected symmetry to be the isolated violation; got: \(laws)"
        )
    }

    @Test func detectsNonTransitiveEquality() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkEquatablePropertyLaws(
                for: RoundingEquatable.self,
                using: Gen<RoundingEquatable>.rounding(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Equatable.transitivity") || laws.contains("Equatable.negationConsistency"),
            "expected transitivity (or negation-consistency fallout) on RoundingEquatable; got: \(laws)"
        )
    }

    // Note: Equatable.negationConsistency is structurally unviolable in Swift
    // (see PlantedEquatableViolators.swift), so there is no planted-bug test
    // for it. The framework still runs the check as defensive documentation.

    // MARK: - Hashable Strict-tier planted bug

    @Test func detectsHashEqualityInconsistency() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkHashablePropertyLaws(
                for: EqualButDifferentHash.self,
                using: Gen<EqualButDifferentHash>.equalButDifferentHash(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Hashable.equalityConsistency"),
            "expected Hashable.equalityConsistency in violation set; got: \(laws)"
        )
    }

    // MARK: - Conventional tier escalation via enforcement: .strict

    @Test func unstableHasherDoesNotThrowByDefault() async throws {
        // The `withKnownIssue` acknowledges the non-fatal issue the kit now records for a
        // Conventional violation under `.default`. Note what this test always *wanted* — "reported
        // as a violation even in default mode" — and note that until the kit recorded an issue, the
        // only place that report existed was a returned array nobody was obliged to read.
        await withKnownIssue("the Conventional violation is visible now — it still does not throw") {
            let results = try await checkHashablePropertyLaws(
                for: UnstableHasher.self,
                using: Gen<UnstableHasher>.unstableHasher(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
            let stability = results.first { $0.protocolLaw == "Hashable.stabilityWithinProcess" }
            #expect(stability != nil)
            #expect(
                stability?.isViolation == true,
                "expected stabilityWithinProcess to be reported as a violation even in default mode"
            )
            #expect(stability?.tier == .conventional)
        }
    }

    @Test func unstableHasherThrowsUnderStrictEnforcement() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkHashablePropertyLaws(
                for: UnstableHasher.self,
                using: Gen<UnstableHasher>.unstableHasher(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Hashable.stabilityWithinProcess"))
    }

    // MARK: - Heuristic tier: distribution

    @Test func detectsDegenerateHashDistribution() async throws {
        // Heuristic tier, so `.default` does not throw — but it does now *speak*, which is what the
        // `withKnownIssue` acknowledges. A degenerate hasher that silently passes is the same defect
        // class as the lossy codec, one tier down.
        await withKnownIssue("the Heuristic violation is visible now — it still does not throw") {
            let results = try await checkHashablePropertyLaws(
                for: DegenerateHasher.self,
                using: Gen<DegenerateHasher>.degenerate(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
            let distribution = results.first { $0.protocolLaw == "Hashable.distribution" }
            #expect(
                distribution?.isViolation == true,
                "expected DegenerateHasher to violate Hashable.distribution"
            )
            #expect(distribution?.tier == .heuristic)
            #expect(distribution?.counterexample?.contains("unique hashValues") == true)
        }
    }

    // MARK: - Inherited Equatable suite re-collection (laws: .all path)

    @Test func collectsInheritedEquatableViolationsWhenLawsIsAll() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkHashablePropertyLaws(
                for: ReflexivityBreakingHashable.self,
                using: Gen<ReflexivityBreakingHashable>.reflexivityBreaking(),
                options: LawCheckOptions(budget: .sanity),
                laws: .all
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Equatable.reflexivity"),
            "expected the inherited Equatable.reflexivity violation; got: \(laws)"
        )
    }

    // MARK: - Comparable Strict-tier planted bugs

    @Test func detectsAntisymmetryViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkComparablePropertyLaws(
                for: BucketedOrder.self,
                using: Gen<BucketedOrder>.bucketedOrder(),
                options: LawCheckOptions(budget: .standard),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Comparable.antisymmetry"),
            "expected antisymmetry in violation set; got: \(laws)"
        )
    }

    @Test func detectsOperatorConsistencyViolation() async throws {
        // `AlwaysLessThan` breaks a Strict law (which throws, as asserted) *and* a lower-tier one
        // alongside it — and the lower-tier one is now recorded rather than dropped. Hence the
        // `withKnownIssue`: the throw is the assertion, the issue is the new visibility.
        await withKnownIssue("the sub-Strict violation alongside it is visible now") {
            let violation = await #expect(throws: PropertyLawViolation.self) {
                try await checkComparablePropertyLaws(
                    for: AlwaysLessThan.self,
                    using: Gen<AlwaysLessThan>.alwaysLessThan(),
                    options: LawCheckOptions(budget: .sanity),
                    laws: .ownOnly
                )
            }
            let laws = violation?.results.map(\.protocolLaw) ?? []
            #expect(
                laws.contains("Comparable.operatorConsistency"),
                "expected operatorConsistency in violation set; got: \(laws)"
            )
        }
    }

    @Test func detectsCyclicOrderTransitivity() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkComparablePropertyLaws(
                for: CyclicOrder.self,
                using: Gen<CyclicOrder>.cyclicOrder(),
                options: LawCheckOptions(budget: .standard),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.isEmpty == false)
        #expect(laws.allSatisfy { $0.hasPrefix("Comparable.") })
    }
}
