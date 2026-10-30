import Testing
import PropertyBased
@testable import PropertyLawKit

/// PRD §8 framework self-test gate, collection-refinements cluster
/// (BidirectionalCollection, RandomAccessCollection, MutableCollection,
/// RangeReplaceableCollection). Split from `PlantedBugCollectionsDetectionTests`
/// so neither suite breaches SwiftLint's type-body length limit.
struct PlantedBugRefinementsDetectionTests {

    // MARK: - BidirectionalCollection Strict-tier planted bug

    @Test func detectsStuckIndexBeforeViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkBidirectionalCollectionPropertyLaws(
                for: StuckIndexBeforeCollection.self,
                using: Gen<StuckIndexBeforeCollection>.stuckIndexBefore(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        // A stuck `index(before:)` breaks all three laws. Accepting any one of
        // them let swift-mutation-testing blind `indexAfterBeforeRoundTrip`
        // twice over while the other two kept this test green.
        let laws = Set(violation?.results.map(\.protocolLaw) ?? [])
        #expect(laws == [
            "BidirectionalCollection.indexBeforeAfterRoundTrip",
            "BidirectionalCollection.indexAfterBeforeRoundTrip",
            "BidirectionalCollection.reverseTraversalConsistency"
        ])
    }

    // MARK: - RandomAccessCollection Strict-tier planted bug

    @Test func detectsWrongDistanceViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkRandomAccessCollectionPropertyLaws(
                for: WrongDistanceCollection.self,
                using: Gen<WrongDistanceCollection>.wrongDistance(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("RandomAccessCollection.distanceConsistency"),
            "expected distanceConsistency; got: \(laws)"
        )
    }

    // MARK: - MutableCollection Strict-tier planted bug

    @Test func detectsNoOpSetterViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkMutableCollectionPropertyLaws(
                for: NoOpSetterCollection.self,
                using: Gen<NoOpSetterCollection>.noOpSetter(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("MutableCollection.swapAtSwapsValues"),
            "expected swapAtSwapsValues; got: \(laws)"
        )
    }

    /// The no-op setter leaves both sides unchanged, so a law that checked
    /// only one side would still catch it. This swap gets `c[i]` right and
    /// `c[j]` wrong.
    @Test func detectsOneSidedSwapViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkMutableCollectionPropertyLaws(
                for: OneSidedSwapCollection.self,
                using: Gen<OneSidedSwapCollection>.oneSidedSwap(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("MutableCollection.swapAtSwapsValues"), "got: \(laws)")
    }

    // MARK: - RangeReplaceableCollection Strict-tier planted bug

    @Test func detectsNoOpReplaceSubrangeViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkRangeReplaceableCollectionPropertyLaws(
                for: NoOpReplaceSubrange.self,
                using: Gen<NoOpReplaceSubrange>.noOpReplaceSubrange(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("RangeReplaceableCollection.replaceSubrangeAppliesEdit"),
            "expected replaceSubrangeAppliesEdit; got: \(laws)"
        )
    }

    /// No other planted collection breaks this law, so it could be switched
    /// off without a test noticing.
    @Test func detectsAppendingInsertViolation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkRangeReplaceableCollectionPropertyLaws(
                for: AppendingInsertCollection.self,
                using: Gen<AppendingInsertCollection>.appendingInsert(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws == ["RangeReplaceableCollection.removeAtInsertRoundTrip"])
    }
}
