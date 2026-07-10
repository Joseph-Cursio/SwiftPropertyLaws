import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate, M3 protocols (IteratorProtocol, Sequence,
/// Collection, SetAlgebra). Split from `PlantedBugDetectionTests` so neither
/// suite breaches SwiftLint's type-body length limit as the kit covers more
/// protocols. Same intent: every Strict-tier law has a planted-bug detection.
struct PlantedBugCollectionsDetectionTests {

    // MARK: - Sequence Strict-tier planted bug

    @Test func detectsLyingUnderestimatedCount() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSequencePropertyLaws(
                for: LyingUnderestimatedCount.self,
                using: Gen<LyingUnderestimatedCount>.lyingUnderestimated(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Sequence.underestimatedCountLowerBound"),
            "expected underestimatedCountLowerBound; got: \(laws)"
        )
    }

    // MARK: - Collection Strict-tier planted bugs

    @Test func detectsCollectionCountConsistencyViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkCollectionPropertyLaws(
                for: OffByOneCountCollection.self,
                using: Gen<OffByOneCountCollection>.offByOneCount(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Collection.countConsistency"),
            "expected countConsistency; got: \(laws)"
        )
    }

    @Test func detectsCollectionIndexValidityViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkCollectionPropertyLaws(
                for: DesyncedSubscriptCollection.self,
                using: Gen<DesyncedSubscriptCollection>.desyncedSubscript(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Collection.indexValidity"),
            "expected indexValidity; got: \(laws)"
        )
    }

    // MARK: - SetAlgebra Strict-tier planted bugs (one per law)

    @Test func detectsSetAlgebraUnionIdempotenceViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: EmptyingUnion.self,
                using: Gen<EmptyingUnion>.emptyingUnion(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.unionIdempotence"),
            "expected unionIdempotence; got: \(laws)"
        )
    }

    @Test func detectsSetAlgebraIntersectionIdempotenceViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: EmptyingIntersection.self,
                using: Gen<EmptyingIntersection>.emptyingIntersection(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.intersectionIdempotence"),
            "expected intersectionIdempotence; got: \(laws)"
        )
    }

    @Test func detectsSetAlgebraUnionCommutativityViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: LeftBiasedUnion.self,
                using: Gen<LeftBiasedUnion>.leftBiasedUnion(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.unionCommutativity"),
            "expected unionCommutativity; got: \(laws)"
        )
    }

    @Test func detectsSetAlgebraIntersectionCommutativityViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: LeftBiasedIntersection.self,
                using: Gen<LeftBiasedIntersection>.leftBiasedIntersection(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.intersectionCommutativity"),
            "expected intersectionCommutativity; got: \(laws)"
        )
    }

    @Test func detectsSetAlgebraEmptyIdentityViolation() async throws {
        // EmptyingUnion violates emptyIdentity in addition to unionIdempotence.
        // Both can surface; this test just asserts emptyIdentity is among them.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: EmptyingUnion.self,
                using: Gen<EmptyingUnion>.emptyingUnion(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.emptyIdentity"),
            "expected emptyIdentity; got: \(laws)"
        )
    }

    @Test func detectsSetAlgebraSymmetricDifferenceViolation() async throws {
        // BuggySymmetricDifference returns intersection from `symmetricDifference`,
        // mirroring the pre-fix swift-collections@35349601 _Bitmap bug. Three of
        // the four symmetricDifference* laws fire (selfIsEmpty, emptyIdentity,
        // definition); commutativity passes vacuously since `&` is commutative.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: BuggySymmetricDifference.self,
                using: Gen<BuggySymmetricDifference>.buggySymmetricDifference(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        let symDiffLaws = Set(laws).intersection([
            "SetAlgebra.symmetricDifferenceSelfIsEmpty",
            "SetAlgebra.symmetricDifferenceEmptyIdentity",
            "SetAlgebra.symmetricDifferenceDefinition"
        ])
        #expect(
            !symDiffLaws.isEmpty,
            "expected at least one symmetricDifference* law to fire; got: \(laws)"
        )
    }

    @Test func detectsSetAlgebraSubtractingViolationOnlyViaDeMorgan() async throws {
        // BuggySubtracting implements `subtracting` as `symmetricDifference` —
        // they agree exactly when the subtrahend is a subset of the minuend,
        // which is the only regime the nine pre-M2 laws ever exercise
        // (symmetricDifferenceDefinition subtracts the intersection from the
        // union). The two De Morgan laws are the new coverage: they subtract
        // operands that stick out of the minuend.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: BuggySubtracting.self,
                using: Gen<BuggySubtracting>.buggySubtracting(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = Set(violation?.results.map(\.protocolLaw) ?? [])
        let deMorganLaws: Set<String> = [
            "SetAlgebra.deMorganForUnion",
            "SetAlgebra.deMorganForIntersection"
        ]
        #expect(
            laws.isDisjoint(with: deMorganLaws) == false,
            "expected a De Morgan law to fire; got: \(laws)"
        )
        #expect(
            laws.subtracting(deMorganLaws).isEmpty,
            "expected ONLY De Morgan laws to fire (the other 13 must pass); got: \(laws)"
        )
    }
}
