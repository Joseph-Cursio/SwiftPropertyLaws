import OrderedCollections
import PropertyBased

/// Seeded generators for `OrderedSet<Int>`.
public extension Gen where Value == OrderedSet<Int> {

    /// An `OrderedSet` built from a seeded small-int array; duplicates in
    /// the source array collapse on insert, so generated sets skew slightly
    /// shorter than `count`'s upper bound. The small element range keeps
    /// duplicate-collapse (and hashable-law collisions) common, which is
    /// exactly the regime where insertion-order bugs would surface.
    static func smallIntOrderedSet(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<OrderedSet<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { OrderedSet($0) }
    }
}
