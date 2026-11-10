import PropertyBased
@testable import PropertyLawKit
import Testing

struct RangeReplaceableCollectionLawsTests {

    @Test func arrayPassesAllLawsIncludingInheritedChain() async throws {
        let results = try await checkRangeReplaceableCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("RangeReplaceableCollection.emptyInitIsEmpty"))
        #expect(names.contains("RangeReplaceableCollection.removeAtInsertRoundTrip"))
        #expect(names.contains("RangeReplaceableCollection.removeAllMakesEmpty"))
        #expect(names.contains("RangeReplaceableCollection.replaceSubrangeAppliesEdit"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func ownOnlySkipsInheritedSuites() async throws {
        let results = try await checkRangeReplaceableCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...4),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.allSatisfy { $0.hasPrefix("RangeReplaceableCollection.") })
    }

    @Test func stringPassesAllLaws() async throws {
        // String is a RangeReplaceableCollection — exercise the
        // remove/insert/replaceSubrange laws against a real stdlib type.
        let results = try await checkRangeReplaceableCollectionPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
