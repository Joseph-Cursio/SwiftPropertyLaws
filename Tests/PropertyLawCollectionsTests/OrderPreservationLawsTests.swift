import OrderedCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

struct OrderPreservationLawsTests {

    @Test func orderedSetOfIntPassesAllOrderPreservationLaws() async throws {
        let results = try await checkOrderPreservationPropertyLaws(
            for: OrderedSet<Int>.self,
            using: Gen<OrderedSet<Int>>.smallIntOrderedSet(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        for law in OrderPreservationLaw.allCases {
            #expect(names.contains("OrderedSet.\(law.rawValue)"), "missing law \(law.rawValue)")
        }
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    /// The metamorphic-pair demonstration: ordered equality on union is NOT
    /// commutative in general — witnessed concretely so the pair of laws
    /// (order-defined vs membership-commutative) can't drift apart silently.
    @Test func unionOrderSensitivityWitness() {
        let left: OrderedSet<Int> = [1, 2]
        let right: OrderedSet<Int> = [3, 1]
        #expect(left.union(right) != right.union(left))
        #expect(Set(left.union(right)) == Set(right.union(left)))
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.orderPreservation(.unionKeepsLeftOrderThenNovelRight)
        #expect(identifier.qualifiedName == "OrderedSet.unionKeepsLeftOrderThenNovelRight")
    }
}
