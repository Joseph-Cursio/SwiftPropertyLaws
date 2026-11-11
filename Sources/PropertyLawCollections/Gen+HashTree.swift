import HashTreeCollections
import PropertyBased

/// Seeded generators for the CHAMP-backed persistent types
/// (`TreeSet` / `TreeDictionary`).
public extension Gen where Value == TreeSet<Int> {

    /// A `TreeSet` built from a seeded small-int array; duplicates collapse
    /// on insert. Small element range keeps overlap between two generated
    /// sets common, which the SetAlgebra binary-op laws need.
    static func smallIntTreeSet(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<TreeSet<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { TreeSet($0) }
    }
}

public extension Gen where Value == TreeDictionary<Int, Int> {

    /// A `TreeDictionary` built from a seeded small-int array: each element
    /// becomes a key with a derived value (`&* 3`), duplicate keys collapse
    /// first-wins — same shape as the OrderedDictionary generator.
    static func smallIntTreeDictionary(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<TreeDictionary<Int, Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { keys in
            var dictionary = TreeDictionary<Int, Int>()
            for key in keys where dictionary[key] == nil {
                dictionary[key] = key &* 3
            }
            return dictionary
        }
    }
}
