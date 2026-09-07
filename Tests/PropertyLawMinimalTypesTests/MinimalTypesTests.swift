import PropertyBased
import PropertyLawKit
import PropertyLawMinimalTypes
import Testing

/// The point of these types is to run the kit's own law suites against something that is not
/// `Array`. A law that passes on `Array` and fails here was relying on a guarantee `Collection`
/// does not make — so these tests check the law suite as much as the conformance.
@Suite("Minimal conformances")
struct MinimalTypesTests {

    @Test("Collection laws hold for the weakest legal Collection")
    func minimalCollectionPassesCollectionChain() async throws {
        let results = try await checkCollectionPropertyLaws(
            for: MinimalCollection<Int>.self,
            using: Gen<MinimalCollection<Int>>.smallIntMinimalCollection(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test("Bidirectional laws hold for the weakest legal BidirectionalCollection")
    func minimalBidirectionalPassesChain() async throws {
        let results = try await checkBidirectionalCollectionPropertyLaws(
            for: MinimalBidirectionalCollection<Int>.self,
            using: Gen<MinimalBidirectionalCollection<Int>>.smallIntMinimalBidirectionalCollection(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    // MARK: - The guarantees these types deliberately withhold

    /// `Array` reports its real count here; `Sequence` promises only a lower bound. A law that
    /// sizes a buffer from `underestimatedCount` passes on `Array` and is wrong in general.
    @Test("MinimalSequence underestimates, as Sequence permits")
    func minimalSequenceUnderestimates() {
        let sequence = MinimalSequence([1, 2, 3, 4, 5])
        #expect(sequence.underestimatedCount == 0)
        #expect(Array(sequence) == [1, 2, 3, 4, 5])
    }

    /// The index carries no arithmetic and no integer conversion, so generic code cannot reach
    /// past `Collection`'s vocabulary the way it can with `Array`'s `Int` index.
    @Test("Indices are ordered but opaque")
    func indicesAreOpaqueButOrdered() {
        let collection = MinimalCollection([10, 20, 30])
        let first = collection.startIndex
        let second = collection.index(after: first)
        #expect(first < second)
        #expect(first != second)
        #expect(collection[first] == 10)
        #expect(collection.distance(from: first, to: second) == 1)
    }

    /// `count`, `distance` and `index(_:offsetBy:)` come from `Collection`'s O(n) defaults
    /// rather than a random-access fast path, which is what makes this a real second
    /// implementation rather than an `Array` in a wrapper.
    @Test("Forward-only traversal still satisfies the count and distance laws")
    func forwardOnlyTraversalIsConsistent() {
        let collection = MinimalCollection(Array(0 ..< 7))
        #expect(collection.count == 7)
        #expect(collection.distance(from: collection.startIndex, to: collection.endIndex) == 7)
        let third = collection.index(collection.startIndex, offsetBy: 3)
        #expect(collection[third] == 3)
        #expect(collection.isEmpty == false)
        #expect(MinimalCollection<Int>([]).isEmpty)
    }

    /// Two instances vend indices that are not interchangeable. Mixing them traps rather than
    /// answering — the behaviour a law suite wants, since the alternative is a quiet wrong
    /// answer that reads as a pass. The trap itself is not exercised here (it is a
    /// `precondition`), but the identities that drive it are.
    @Test("Indices from different collections are distinguishable")
    func indicesCarryTheirProvenance() {
        let left = MinimalCollection([1, 2, 3])
        let right = MinimalCollection([1, 2, 3])
        #expect(left.startIndex.hashValue != right.startIndex.hashValue)
    }
}
