import DequeModule
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// M1 law runs for `Deque<Int>` — the protocol-richest swift-collections
/// type. Follows the discovery plugin's most-specific-per-chain convention:
/// one `.all` run for the RandomAccess → Bidirectional → Collection →
/// Sequence → Iterator chain, `.ownOnly` for the independent sibling
/// refinements (Mutable, RangeReplaceable), and Hashable `.all` covering
/// Equatable.
struct DequeLawsTests {

    @Test func dequePassesRandomAccessCollectionChain() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("BidirectionalCollection.indexBeforeAfterRoundTrip"))
        #expect(names.contains("RandomAccessCollection.distanceConsistency"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesMutableCollectionLaws() async throws {
        let results = try await checkMutableCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesRangeReplaceableCollectionLaws() async throws {
        let results = try await checkRangeReplaceableCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains { $0.hasPrefix("Equatable.") })
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
