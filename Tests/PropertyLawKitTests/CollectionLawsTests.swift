import PropertyBased
@testable import PropertyLawKit
import Testing

struct CollectionLawsTests {

    @Test func arrayPassesAllLawsIncludingInheritedSequenceAndIterator() async throws {
        let results = try await checkCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        // Inherited chain from §4.3: Iterator → Sequence → Collection.
        #expect(names.contains("IteratorProtocol.terminationStability"))
        #expect(names.contains("Sequence.underestimatedCountLowerBound"))
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("Collection.indexValidity"))
        #expect(names.contains("Collection.nonMutation"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func ownOnlySkipsInheritedSequenceAndIteratorSuites() async throws {
        let results = try await checkCollectionPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...4),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.allSatisfy { $0.hasPrefix("Collection.") })
    }

    @Test func detectsOffByOneCount() async throws {
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

    @Test func detectsDesyncedSubscript() async throws {
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

    @Test func stringPassesAllLaws() async throws {
        // Strings are Bidirectional Collections of Character — exercise the
        // forward-only Collection laws with a real stdlib type.
        let results = try await checkCollectionPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
