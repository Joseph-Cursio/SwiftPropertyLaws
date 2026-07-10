import OrderedCollections
import PropertyBased

/// Seeded generators for `OrderedDictionary<Int, Int>`.
public extension Gen where Value == OrderedDictionary<Int, Int> {

    /// An `OrderedDictionary` built from a seeded small-int array: each
    /// element becomes a key, with a value derived from it (`&* 3` keeps
    /// values distinct from keys without a second seeded stream). Duplicate
    /// keys collapse first-wins, so insertion order is preserved for the
    /// surviving entries — the regime OrderedDictionary exists to protect.
    static func smallIntOrderedDictionary(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<OrderedDictionary<Int, Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { keys in
            OrderedDictionary(
                keys.map { key in (key, key &* 3) },
                uniquingKeysWith: { first, _ in first }
            )
        }
    }
}
