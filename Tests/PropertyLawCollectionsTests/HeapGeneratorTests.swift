import HeapModule
import PropertyBased
import PropertyLawCollections
import Testing

/// M1 smoke coverage for the `Heap<Int>` generator. No existing law family
/// applies (audit-confirmed: Heap is not Sequence/Collection), so this
/// pins the generator's basic contract until M3's model-based HeapLaws
/// land — drain-equals-sorted and min-lower-bound are specified in the
/// collections/async workplan.
struct HeapGeneratorTests {

    @Test func generatedHeapPreservesElementCountAndBounds() async throws {
        var rng: any SeededRandomNumberGenerator =
            Xoshiro(seed: (7, 8, 9, 10))
        let generator = Gen<Heap<Int>>.smallIntHeap()
        for _ in 0 ..< 100 {
            let heap = generator.run(using: &rng)
            #expect(heap.count <= 8)
            if let minimum = heap.min, let maximum = heap.max {
                #expect(minimum <= maximum)
            } else {
                #expect(heap.isEmpty)
            }
        }
    }
}
