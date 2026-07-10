import PropertyBased

/// Planted violator for the M2 Boolean-algebra laws: `subtracting` is
/// implemented as `symmetricDifference` — the classic confusion, since the
/// two agree exactly when the subtrahend is a subset of the minuend.
///
/// **Passes all nine pre-M2 laws**, including `symmetricDifferenceDefinition`:
/// that law computes `(x ∪ y).subtracting(x ∩ y)`, and the intersection is
/// always a subset of the union, so the buggy `subtracting` returns the
/// right answer there. Only the two De Morgan laws exercise `subtracting`
/// with operands that stick out of the minuend, where `x △ y` picks up
/// elements of `y \ x` that a true difference would drop.
struct BuggySubtracting: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    func union(_ other: BuggySubtracting) -> BuggySubtracting {
        BuggySubtracting(underlying.union(other.underlying))
    }
    func intersection(_ other: BuggySubtracting) -> BuggySubtracting {
        BuggySubtracting(underlying.intersection(other.underlying))
    }
    func symmetricDifference(_ other: BuggySubtracting) -> BuggySubtracting {
        BuggySubtracting(underlying.symmetricDifference(other.underlying))
    }

    // The bug: subtracting returns the symmetric difference.
    func subtracting(_ other: BuggySubtracting) -> BuggySubtracting {
        BuggySubtracting(underlying.symmetricDifference(other.underlying))
    }
    mutating func subtract(_ other: BuggySubtracting) {
        underlying.formSymmetricDifference(other.underlying)
    }

    mutating func formUnion(_ other: BuggySubtracting) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_ other: BuggySubtracting) {
        underlying.formIntersection(other.underlying)
    }
    mutating func formSymmetricDifference(_ other: BuggySubtracting) {
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

    static func == (lhs: BuggySubtracting, rhs: BuggySubtracting) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String { "BSub(\(underlying.sorted()))" }
}

extension Gen where Value == BuggySubtracting {
    /// Generator for `BuggySubtracting`. Same shape as
    /// `buggySymmetricDifference()`: the small element range yields both
    /// overlapping and disjoint triples, and De Morgan needs operands that
    /// stick out of the minuend for the bug to surface.
    static func buggySubtracting() -> Generator<BuggySubtracting, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4)
            .map { BuggySubtracting(Set($0)) }
    }
}
