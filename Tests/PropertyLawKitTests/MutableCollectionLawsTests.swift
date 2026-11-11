import PropertyBased
@testable import PropertyLawKit
import Testing

struct MutableCollectionLawsTests {

    @Test func arrayPassesAllLawsIncludingInheritedChain() async throws {
        let results = try await checkMutableCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("MutableCollection.swapAtSwapsValues"))
        #expect(names.contains("MutableCollection.swapAtInvolution"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func ownOnlySkipsInheritedSuites() async throws {
        let results = try await checkMutableCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...4),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.allSatisfy { $0.hasPrefix("MutableCollection.") })
    }
}
