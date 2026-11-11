import PropertyBased
@testable import PropertyLawKit
import Testing

struct RandomAccessCollectionLawsTests {

    @Test func arrayPassesAllLawsIncludingInheritedChain() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("BidirectionalCollection.indexBeforeAfterRoundTrip"))
        #expect(names.contains("RandomAccessCollection.distanceConsistency"))
        #expect(names.contains("RandomAccessCollection.offsetConsistency"))
        #expect(names.contains("RandomAccessCollection.negativeOffsetInversion"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func ownOnlySkipsInheritedSuites() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...4),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.allSatisfy { $0.hasPrefix("RandomAccessCollection.") })
    }
}
