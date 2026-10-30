import PropertyBased

// MARK: - BidirectionalCollection planted bug

/// BidirectionalCollection whose `index(before:)` is a no-op — the index
/// doesn't move backward at all. Violates
/// `BidirectionalCollection.indexBeforeAfterRoundTrip` (and the other two
/// bidirectional laws) because `index(before: index(after: i))` returns
/// `i + 1`, not `i`.
struct StuckIndexBeforeCollection: BidirectionalCollection, Sendable, CustomStringConvertible {
    let storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    func index(before position: Int) -> Int { position }  // the bug

    subscript(position: Int) -> Int { storage[position] }

    var description: String { "StuckIndexBefore(\(storage))" }
}

extension Gen where Value == StuckIndexBeforeCollection {
    static func stuckIndexBefore() -> Generator<
        StuckIndexBeforeCollection, some SendableSequenceType
    > {
        Gen<Int>.int(in: 0...10)
            .array(of: 2...4)
            .map { StuckIndexBeforeCollection(storage: $0) }
    }
}

// MARK: - RandomAccessCollection planted bug

/// RandomAccessCollection whose `distance(from:to:)` returns the wrong sign.
/// Forward-walking via `index(after:)` works (inherited from Collection);
/// only the random-access shortcut lies. Violates
/// `RandomAccessCollection.distanceConsistency`.
struct WrongDistanceCollection: RandomAccessCollection, Sendable, CustomStringConvertible {
    let storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    func index(before position: Int) -> Int { position - 1 }

    func distance(from start: Int, to end: Int) -> Int {
        // The bug: returns the absolute distance, dropping the sign.
        // For start <= end the answer is correct; for start > end the
        // expected value is negative and the lie surfaces.
        Swift.abs(end - start)
    }

    subscript(position: Int) -> Int { storage[position] }

    var description: String { "WrongDistance(\(storage))" }
}

extension Gen where Value == WrongDistanceCollection {
    static func wrongDistance() -> Generator<
        WrongDistanceCollection, some SendableSequenceType
    > {
        Gen<Int>.int(in: 0...10)
            .array(of: 2...4)
            .map { WrongDistanceCollection(storage: $0) }
    }
}

// MARK: - MutableCollection planted bug

/// MutableCollection whose subscript setter is a no-op. The getter still
/// returns the original element, so `c.swapAt(i, j)` (whose default impl
/// goes through subscript get + set) leaves both elements unchanged.
/// Violates `MutableCollection.swapAtSwapsValues` (but, deceptively, NOT
/// `swapAtInvolution` — a no-op composed with a no-op is identity).
struct NoOpSetterCollection: MutableCollection, Sendable, CustomStringConvertible {
    var storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }

    subscript(position: Int) -> Int {
        get { storage[position] }
        // swiftlint:disable:next unused_setter_value
        set { /* the bug — write is dropped */ }
    }

    var description: String { "NoOpSetter(\(storage))" }
}

extension Gen where Value == NoOpSetterCollection {
    static func noOpSetter() -> Generator<NoOpSetterCollection, some SendableSequenceType> {
        // Pairs of distinct values so a working setter would observably
        // swap them — without distinct values, swapAtSwapsValues passes
        // vacuously even on a broken setter.
        Gen<Int>.int(in: 0...3)
            .array(of: 2...4)
            .map { values -> NoOpSetterCollection in
                var deduped = values
                for offset in deduped.indices {
                    deduped[offset] = offset &* 7 &+ values[offset]
                }
                return NoOpSetterCollection(storage: deduped)
            }
    }
}

/// MutableCollection whose `swapAt` writes one side only: `c[i]` takes
/// `c[j]`'s value and `c[j]` keeps its own. The subscript works, so only the
/// swap is wrong. The no-op setter above leaves both sides unchanged, so it
/// cannot show that `swapAtSwapsValues` checks each side on its own.
struct OneSidedSwapCollection: MutableCollection, Sendable, CustomStringConvertible {
    var storage: [Int]

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }

    subscript(position: Int) -> Int {
        get { storage[position] }
        set { storage[position] = newValue }
    }

    mutating func swapAt(_ first: Int, _ second: Int) {
        storage[first] = storage[second]  // the bug — `second` is never written
    }

    var description: String { "OneSidedSwap(\(storage))" }
}

extension Gen where Value == OneSidedSwapCollection {
    /// Distinct values, so a lost write is visible.
    static func oneSidedSwap() -> Generator<OneSidedSwapCollection, some SendableSequenceType> {
        Gen<Int>.int(in: 0...3)
            .array(of: 2...4)
            .map { values in
                OneSidedSwapCollection(storage: values.indices.map { $0 &* 7 &+ values[$0] })
            }
    }
}

// MARK: - RangeReplaceableCollection planted bug

/// RangeReplaceableCollection whose `replaceSubrange(_:with:)` is a no-op.
/// The single-method bug reproduces the typical real-world failure mode of a
/// custom collection where the protocol's one mutating requirement is
/// misimplemented.
///
/// **Only `replaceSubrangeAppliesEdit` fails** (measured 2026-10-29). This
/// comment used to say every law did. `removeAll()` reaches the correct
/// `init()`, and a `remove(at:)` and an `insert(_:at:)` that both do nothing
/// leave the collection as it was, so the round trip holds.
/// `AppendingInsertCollection` below is the violator for that law.
struct NoOpReplaceSubrange: RangeReplaceableCollection, Sendable, CustomStringConvertible {
    var storage: [Int]

    init() { self.storage = [] }
    init(storage: [Int]) { self.storage = storage }

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    subscript(position: Int) -> Int { storage[position] }

    mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Int {
        // the bug — no edit applied
    }

    var description: String { "NoOpReplace(\(storage))" }
}

extension Gen where Value == NoOpReplaceSubrange {
    static func noOpReplaceSubrange() -> Generator<
        NoOpReplaceSubrange, some SendableSequenceType
    > {
        Gen<Int>.int(in: 0...10)
            .array(of: 1...4)
            .map { NoOpReplaceSubrange(storage: $0) }
    }
}

/// RangeReplaceableCollection whose `insert(_:at:)` ignores the position and
/// appends. `replaceSubrange` is correct, so `remove(at:)` works and every
/// other law passes; removing an element and inserting it back where it was
/// moves it to the end. `NoOpReplaceSubrange` cannot catch this law: a
/// remove and an insert that both do nothing leave the collection as it was.
struct AppendingInsertCollection: RangeReplaceableCollection, Sendable, CustomStringConvertible {
    var storage: [Int]

    init() { self.storage = [] }
    init(storage: [Int]) { self.storage = storage }

    var startIndex: Int { 0 }
    var endIndex: Int { storage.count }

    func index(after position: Int) -> Int { position + 1 }
    subscript(position: Int) -> Int { storage[position] }

    mutating func replaceSubrange<C: Collection>(
        _ subrange: Range<Int>,
        with newElements: C
    ) where C.Element == Int {
        storage.replaceSubrange(subrange, with: newElements)
    }

    mutating func insert(_ newElement: Int, at position: Int) {
        storage.append(newElement)  // the bug — `position` is ignored
    }

    var description: String { "AppendingInsert(\(storage))" }
}

extension Gen where Value == AppendingInsertCollection {
    /// Two or more distinct values, so an element moved to the end is visible.
    static func appendingInsert() -> Generator<AppendingInsertCollection, some SendableSequenceType> {
        Gen<Int>.int(in: 0...3)
            .array(of: 2...4)
            .map { values in
                AppendingInsertCollection(storage: values.indices.map { $0 &* 7 &+ values[$0] })
            }
    }
}
