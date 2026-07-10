import BitCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// M1 law runs for `BitSet` — the full-SetAlgebra carrier that motivates
/// M2's family completion (distributivity / absorption / relative
/// De Morgan). Collection-wise BitSet tops out at BidirectionalCollection
/// (audit-confirmed no RandomAccess), so that chain runs `.all`.
struct BitSetLawsTests {

    @Test func bitSetPassesSetAlgebraLaws() async throws {
        let results = try await checkSetAlgebraPropertyLaws(
            for: BitSet.self,
            using: Gen<BitSet>.smallBitSet(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("SetAlgebra.unionCommutativity"))
        #expect(names.contains("SetAlgebra.symmetricDifferenceDefinition"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func bitSetPassesBidirectionalCollectionChain() async throws {
        let results = try await checkBidirectionalCollectionPropertyLaws(
            for: BitSet.self,
            using: Gen<BitSet>.smallBitSet(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("BidirectionalCollection.indexBeforeAfterRoundTrip"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func bitSetPassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: BitSet.self,
            using: Gen<BitSet>.smallBitSet(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func bitSetPassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: BitSet.self,
            using: Gen<BitSet>.smallBitSet(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
