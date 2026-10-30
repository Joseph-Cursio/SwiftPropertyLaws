import PropertyBased

/// SetAlgebra wrapper whose non-mutating operations are all correct but whose
/// `formUnion(_:)` performs an intersection. The mutating twin disagrees with
/// its non-mutating original.
///
/// This is the violator that motivated the four `*Matches*` laws. Every one of
/// the fifteen laws that preceded them is stated over the non-mutating
/// operations only, so this type passes all fifteen: `union`, `intersection`,
/// `symmetricDifference` and `subtracting` are untouched, and no law ever
/// calls `formUnion`. `PlantedBugCollectionsDetectionTests` asserts both
/// halves — that `formUnionMatchesUnion` fires, and that none of the fifteen
/// do — so the gap the new laws close stays demonstrated rather than asserted.
struct DivergentFormUnion: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    func union(_ other: DivergentFormUnion) -> DivergentFormUnion {
        DivergentFormUnion(underlying.union(other.underlying))
    }
    func intersection(_ other: DivergentFormUnion) -> DivergentFormUnion {
        DivergentFormUnion(underlying.intersection(other.underlying))
    }
    func symmetricDifference(_ other: DivergentFormUnion) -> DivergentFormUnion {
        DivergentFormUnion(underlying.symmetricDifference(other.underlying))
    }

    // The bug: the mutating twin intersects where its original unions.
    mutating func formUnion(_ other: DivergentFormUnion) {
        underlying.formIntersection(other.underlying)
    }

    mutating func formIntersection(_ other: DivergentFormUnion) {
        underlying.formIntersection(other.underlying)
    }
    mutating func formSymmetricDifference(_ other: DivergentFormUnion) {
        underlying.formSymmetricDifference(other.underlying)
    }

    @discardableResult
    mutating func insert(
        _ newMember: Int
    ) -> (inserted: Bool, memberAfterInsert: Int) {
        underlying.insert(newMember)
    }
    @discardableResult
    mutating func remove(_ member: Int) -> Int? { underlying.remove(member) }
    @discardableResult
    mutating func update(with newMember: Int) -> Int? {
        underlying.update(with: newMember)
    }

    static func == (lhs: DivergentFormUnion, rhs: DivergentFormUnion) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String { "DFU(\(underlying.sorted()))" }
}

extension Gen where Value == DivergentFormUnion {
    /// Generator for `DivergentFormUnion`. Needs pairs that are not subsets of
    /// each other: when `y ⊆ x`, `x.formUnion(y)` and `x.union(y)` agree by
    /// accident, and the law passes vacuously on that sample.
    static func divergentFormUnion() -> Generator<DivergentFormUnion, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4)
            .map { DivergentFormUnion(Set($0)) }
    }
}
