import HeapModule
import PropertyBased

/// Seeded generators for `Heap<Int>`.
public extension Gen where Value == Heap<Int> {

    /// A `Heap` built from a seeded small-int array (duplicates kept —
    /// heaps are multisets). Per the conformance audit, `Heap` sits outside
    /// the Sequence/Collection lattice entirely, so no existing law family
    /// consumes this generator yet; it ships in M1 as the carrier for M3's
    /// model-based HeapLaws (drain-equals-sorted, min-lower-bound).
    static func smallIntHeap(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<Heap<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { Heap($0) }
    }
}
