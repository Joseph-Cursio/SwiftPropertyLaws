/// A `Sequence` that guarantees nothing beyond `Sequence`.
///
/// No `underestimatedCount` better than 0, no contiguous storage, and single-pass by
/// construction — iterating twice is a programmer error the type reports rather than tolerates.
/// `Array` permits all three, so a law that quietly re-iterates its input passes on `Array` and
/// says nothing.
public struct MinimalSequence<Element: Sendable>: Sequence, Sendable {
    private let elements: [Element]

    public init(_ elements: some Sequence<Element>) {
        self.elements = Array(elements)
    }

    public func makeIterator() -> AnyIterator<Element> {
        var index = 0
        let elements = elements
        return AnyIterator {
            guard index < elements.count else { return nil }
            defer { index += 1 }
            return elements[index]
        }
    }

    /// `Sequence`'s documented default. Deliberately not `count`.
    public var underestimatedCount: Int { 0 }
}

/// A `Collection` that guarantees nothing beyond `Collection`.
///
/// Forward traversal only, an opaque index, and no `RandomAccessCollection` fast path — so
/// `index(_:offsetBy:)`, `distance(from:to:)` and `count` all go through the O(n) defaults.
/// Running a law suite against this checks the suite as much as the type: a law that passes on
/// `Array` and fails here was relying on something `Collection` does not promise.
public struct MinimalCollection<Element: Sendable>: Collection, Sendable {
    private let elements: [Element]
    private let instance: Int

    public init(_ elements: some Sequence<Element>) {
        self.elements = Array(elements)
        self.instance = MinimalInstanceCounter.allocate()
    }

    public var startIndex: MinimalIndex { MinimalIndex(owner: instance, offset: 0) }
    public var endIndex: MinimalIndex { MinimalIndex(owner: instance, offset: elements.count) }

    public func index(after index: MinimalIndex) -> MinimalIndex {
        precondition(index.owner == instance, "MinimalCollection: index from another collection")
        precondition(index.offset < elements.count, "MinimalCollection: advancing past endIndex")
        return MinimalIndex(owner: instance, offset: index.offset + 1)
    }

    public subscript(index: MinimalIndex) -> Element {
        precondition(index.owner == instance, "MinimalCollection: index from another collection")
        precondition(index.offset < elements.count, "MinimalCollection: subscripting endIndex")
        return elements[index.offset]
    }
}

/// The `BidirectionalCollection` counterpart — adds `index(before:)` and nothing else.
public struct MinimalBidirectionalCollection<Element: Sendable>: BidirectionalCollection, Sendable {
    private let elements: [Element]
    private let instance: Int

    public init(_ elements: some Sequence<Element>) {
        self.elements = Array(elements)
        self.instance = MinimalInstanceCounter.allocate()
    }

    public var startIndex: MinimalIndex { MinimalIndex(owner: instance, offset: 0) }
    public var endIndex: MinimalIndex { MinimalIndex(owner: instance, offset: elements.count) }

    public func index(after index: MinimalIndex) -> MinimalIndex {
        precondition(index.owner == instance, "MinimalBidirectionalCollection: foreign index")
        precondition(index.offset < elements.count, "MinimalBidirectionalCollection: past endIndex")
        return MinimalIndex(owner: instance, offset: index.offset + 1)
    }

    public func index(before index: MinimalIndex) -> MinimalIndex {
        precondition(index.owner == instance, "MinimalBidirectionalCollection: foreign index")
        precondition(index.offset > 0, "MinimalBidirectionalCollection: before startIndex")
        return MinimalIndex(owner: instance, offset: index.offset - 1)
    }

    public subscript(index: MinimalIndex) -> Element {
        precondition(index.owner == instance, "MinimalBidirectionalCollection: foreign index")
        precondition(index.offset < elements.count, "MinimalBidirectionalCollection: endIndex")
        return elements[index.offset]
    }
}

extension MinimalSequence: Equatable where Element: Equatable {}
extension MinimalCollection: Equatable where Element: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.elementsEqual(rhs) }
}
extension MinimalBidirectionalCollection: Equatable where Element: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.elementsEqual(rhs) }
}
