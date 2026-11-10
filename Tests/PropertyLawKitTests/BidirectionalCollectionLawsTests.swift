import PropertyBased
@testable import PropertyLawKit
import Testing

struct BidirectionalCollectionLawsTests {

    @Test func arrayPassesAllLawsIncludingInheritedChain() async throws {
        let results = try await checkBidirectionalCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("IteratorProtocol.terminationStability"))
        #expect(names.contains("Sequence.underestimatedCountLowerBound"))
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("BidirectionalCollection.indexBeforeAfterRoundTrip"))
        #expect(names.contains("BidirectionalCollection.indexAfterBeforeRoundTrip"))
        #expect(names.contains("BidirectionalCollection.reverseTraversalConsistency"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func ownOnlySkipsInheritedSuites() async throws {
        let results = try await checkBidirectionalCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...4),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.allSatisfy { $0.hasPrefix("BidirectionalCollection.") })
    }

    @Test func stringPassesAllLaws() async throws {
        // String is a BidirectionalCollection of Character — exercise the
        // forward+backward index walks against a real stdlib type.
        let results = try await checkBidirectionalCollectionPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
