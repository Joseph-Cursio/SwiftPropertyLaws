import PropertyBased

/// Collection whose stored `count` is inconsistent with the iterated element
/// count. Backed by an Array; reports `count + 1`. Violates
/// Collection.countConsistency.
struct OffByOneCountCollection: Collection, Sendable, CustomStringConvertible {
    let storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }
    var count: Int { storage.count + 1 } // the lie

    func index(after index: Int) -> Int { index + 1 }
    subscript(position: Int) -> Int { storage[position] }

    var description: String { "OffByOne(\(storage))" }
}

/// Collection whose subscript returns a different value than Sequence
/// iteration would. Violates Collection.indexValidity (the index walk and
/// sequence iteration disagree).
struct DesyncedSubscriptCollection: Collection, Sendable, CustomStringConvertible {
    let storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }
    var count: Int { storage.count }

    func index(after index: Int) -> Int { index + 1 }

    // Subscript returns -1 for every position; the default Sequence iterator
    // built on top of subscript will see -1s, so to make iteration disagree
    // with subscript we provide a custom makeIterator that uses storage.
    func makeIterator() -> IndexingIterator<[Int]> { storage.makeIterator() }

    subscript(_: Int) -> Int { -1 }

    var description: String { "Desynced(\(storage))" }
}

extension Gen where Value == OffByOneCountCollection {
    static func offByOneCount() -> Generator<OffByOneCountCollection, some SendableSequenceType> {
        Gen<Int>.int(in: 0...10)
            .array(of: 1...4)
            .map { OffByOneCountCollection(storage: $0) }
    }
}

extension Gen where Value == DesyncedSubscriptCollection {
    static func desyncedSubscript() -> Generator<DesyncedSubscriptCollection, some SendableSequenceType> {
        Gen<Int>.int(in: 1...10)
            .array(of: 1...4)
            .map { DesyncedSubscriptCollection(storage: $0) }
    }
}
