import HeapModule
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

struct HeapLawsTests {

    @Test func heapOfIntPassesAllHeapLaws() async throws {
        let results = try await checkHeapPropertyLaws(
            for: Heap<Int>.self,
            using: Gen<Heap<Int>>.smallIntHeap(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        for law in HeapLaw.allCases {
            #expect(names.contains("Heap.\(law.rawValue)"), "missing law \(law.rawValue)")
        }
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.heap(.drainMinYieldsSortedAscending)
        #expect(identifier.qualifiedName == "Heap.drainMinYieldsSortedAscending")
    }
}
