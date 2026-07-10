import DequeModule
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

struct DequeSymmetryLawsTests {

    @Test func dequeOfIntPassesAllSymmetryLaws() async throws {
        let results = try await checkDequeSymmetryPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        for law in DequeSymmetryLaw.allCases {
            #expect(names.contains("Deque.\(law.rawValue)"), "missing law \(law.rawValue)")
        }
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.dequeSymmetry(.prependPopFirstRoundTrips)
        #expect(identifier.qualifiedName == "Deque.prependPopFirstRoundTrips")
    }
}
