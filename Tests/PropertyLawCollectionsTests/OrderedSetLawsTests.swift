import OrderedCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// M1 law runs for `OrderedSet<Int>`. Per the conformance audit,
/// `OrderedSet` is deliberately NOT `SetAlgebra` (its set operations are
/// order-asymmetric), so no SetAlgebra run appears here — the
/// order-sensitivity itself becomes M3's OrderPreservationLaws family.
struct OrderedSetLawsTests {

    @Test func orderedSetPassesRandomAccessCollectionChain() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: OrderedSet<Int>.self,
            using: Gen<OrderedSet<Int>>.smallIntOrderedSet(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("RandomAccessCollection.distanceConsistency"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func orderedSetPassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: OrderedSet<Int>.self,
            using: Gen<OrderedSet<Int>>.smallIntOrderedSet(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains { $0.hasPrefix("Equatable.") })
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func orderedSetPassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: OrderedSet<Int>.self,
            using: Gen<OrderedSet<Int>>.smallIntOrderedSet(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
