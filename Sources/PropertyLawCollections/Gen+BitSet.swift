import BitCollections
import PropertyBased

/// Seeded generators for `BitSet`.
public extension Gen where Value == BitSet {

    /// A `BitSet` built from a seeded array of small non-negative ints
    /// (`BitSet` members must be non-negative). The tight `0...64` range
    /// straddles a word boundary, so generated sets exercise both the
    /// single-word fast path and multi-word storage, and overlap between
    /// two generated sets is common — the regime SetAlgebra's binary-op
    /// laws (union/intersection/symmetricDifference) need to bite.
    static func smallBitSet(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<BitSet, some SendableSequenceType> {
        Gen<Int>.int(in: 0 ... 64).array(of: count).map { BitSet($0) }
    }
}
