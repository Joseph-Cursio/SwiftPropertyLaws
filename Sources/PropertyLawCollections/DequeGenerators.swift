import DequeModule
import PropertyBased

/// Seeded generators for `Deque<Int>`.
///
/// Phase 1 M1 binds element types to `Int`, matching SwiftInferProperties'
/// existing OrderedCollections recipes (see the workplan's Open decisions);
/// widening to generic elements is deferred until a consumer needs it.
public extension Gen where Value == Deque<Int> {

    /// A `Deque` built from a seeded small-int array. Element range mirrors
    /// the kit's `TestGen.smallInt()` convention (small magnitudes so
    /// hashable-law collisions stay likely); length `0...8` keeps the
    /// per-trial cost of the collection-law chains flat.
    static func smallIntDeque(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<Deque<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { Deque($0) }
    }
}
