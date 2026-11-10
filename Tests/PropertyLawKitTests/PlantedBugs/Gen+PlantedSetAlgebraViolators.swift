import PropertyBased

/// SetAlgebra wrapper whose `union(_:)` returns `self` unchanged, ignoring
/// the right-hand side. Idempotence and emptyIdentity vacuously pass
/// (`x.union(x)` and `x.union(empty)` both return `x`), but commutativity
/// fails: `a.union(b) = a`, `b.union(a) = b`, and the two differ when
/// `a != b`.
struct LeftBiasedUnion: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    // The bug: union returns self instead of merging the two operands.
    func union(_: Self) -> Self { self }

    func intersection(_ other: Self) -> Self {
        Self(underlying.intersection(other.underlying))
    }
    func symmetricDifference(_ other: Self) -> Self {
        Self(underlying.symmetricDifference(other.underlying))
    }

    mutating func formUnion(_ other: Self) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_ other: Self) {
        underlying.formIntersection(other.underlying)
    }
    mutating func formSymmetricDifference(_ other: Self) {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String {
        "LBU(\(underlying.sorted()))"
    }
}

/// SetAlgebra wrapper whose `intersection(_:)` returns the empty set
/// unconditionally — violates intersectionIdempotence whenever the input is
/// non-empty.
struct EmptyingIntersection: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    func union(_ other: Self) -> Self {
        Self(underlying.union(other.underlying))
    }

    // The bug: intersection always returns the empty set.
    func intersection(_: Self) -> Self {
        Self()
    }

    func symmetricDifference(_ other: Self) -> Self {
        Self(underlying.symmetricDifference(other.underlying))
    }

    mutating func formUnion(_ other: Self) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_: Self) {
        underlying = []
    }
    mutating func formSymmetricDifference(_ other: Self) {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String {
        "EI(\(underlying.sorted()))"
    }
}

/// SetAlgebra wrapper whose `union(_:)` returns the empty set unconditionally.
/// Violates unionIdempotence (`x.union(x) = empty ≠ x` when `x` is non-empty)
/// and emptyIdentity (`x.union(Self()) = empty ≠ x`). Commutativity passes
/// vacuously since both sides are empty.
struct EmptyingUnion: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    // The bug: union always returns empty.
    func union(_: Self) -> Self { Self() }

    func intersection(_ other: Self) -> Self {
        Self(underlying.intersection(other.underlying))
    }
    func symmetricDifference(_ other: Self) -> Self {
        Self(underlying.symmetricDifference(other.underlying))
    }

    mutating func formUnion(_: Self) { underlying = [] }
    mutating func formIntersection(_ other: Self) {
        underlying.formIntersection(other.underlying)
    }
    mutating func formSymmetricDifference(_ other: Self) {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String { "EU(\(underlying.sorted()))" }
}

/// SetAlgebra wrapper whose `intersection(_:)` returns `self`, ignoring the
/// right-hand side. Idempotence and emptyIdentity hold; commutativity fails:
/// `a.intersection(b) = a`, `b.intersection(a) = b`.
struct LeftBiasedIntersection: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    func union(_ other: Self) -> Self {
        Self(underlying.union(other.underlying))
    }

    // The bug: intersection returns self instead of the actual intersection.
    func intersection(_: Self) -> Self { self }

    func symmetricDifference(_ other: Self) -> Self {
        Self(underlying.symmetricDifference(other.underlying))
    }

    mutating func formUnion(_ other: Self) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_: Self) {
        // intentionally a no-op to mirror the lying intersection above
    }
    mutating func formSymmetricDifference(_ other: Self) {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String { "LBI(\(underlying.sorted()))" }
}

/// SetAlgebra wrapper whose `symmetricDifference(_:)` returns the
/// intersection. Mirrors the pre-fix `swift-collections@35349601` `_Bitmap`
/// bug, where `symmetricDifference` was implemented as `&` (intersection)
/// rather than `^` (xor). Violates:
///
/// - `symmetricDifferenceSelfIsEmpty` — `x △ x` returns `x ∩ x = x`,
///   not the empty set, whenever `x` is non-empty.
/// - `symmetricDifferenceEmptyIdentity` — `x △ ∅` returns `x ∩ ∅ = ∅`,
///   not `x`, whenever `x` is non-empty.
/// - `symmetricDifferenceDefinition` — `x △ y` returns `x ∩ y`, not
///   `(x ∪ y) \ (x ∩ y)`, whenever the two sets differ.
///
/// Commutativity is *not* violated: `x ∩ y == y ∩ x`. That's why the kit's
/// original five-law SetAlgebra suite (which had only `*Commutativity` and
/// `*Idempotence` for union/intersection plus `emptyIdentity`) couldn't
/// catch the real-world bug — none of those laws exercise the symmetric
/// difference operation.
struct BuggySymmetricDifference: SetAlgebra, Equatable, Sendable, CustomStringConvertible {
    typealias Element = Int

    var underlying: Set<Int>

    init() { self.underlying = [] }
    init(_ elements: Set<Int>) { self.underlying = elements }

    func contains(_ member: Int) -> Bool { underlying.contains(member) }

    func union(_ other: Self) -> Self {
        Self(underlying.union(other.underlying))
    }
    func intersection(_ other: Self) -> Self {
        Self(underlying.intersection(other.underlying))
    }

    // The bug: symmetricDifference returns the intersection.
    func symmetricDifference(_ other: Self) -> Self {
        Self(underlying.intersection(other.underlying))
    }

    mutating func formUnion(_ other: Self) {
        underlying.formUnion(other.underlying)
    }
    mutating func formIntersection(_ other: Self) {
        underlying.formIntersection(other.underlying)
    }
    mutating func formSymmetricDifference(_ other: Self) {
        underlying.formIntersection(other.underlying)
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

    static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.underlying == rhs.underlying
    }

    var description: String { "BSD(\(underlying.sorted()))" }
}

extension Gen where Value == LeftBiasedUnion {
    static func leftBiasedUnion() -> Generator<LeftBiasedUnion, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 0...4)
            .map { LeftBiasedUnion(Set($0)) }
    }
}

extension Gen where Value == EmptyingIntersection {
    static func emptyingIntersection() -> Generator<EmptyingIntersection, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4) // at least one element so idempotence is non-trivial
            .map { EmptyingIntersection(Set($0)) }
    }
}

extension Gen where Value == EmptyingUnion {
    static func emptyingUnion() -> Generator<EmptyingUnion, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4) // at least one element so idempotence violation is non-trivial
            .map { EmptyingUnion(Set($0)) }
    }
}

extension Gen where Value == LeftBiasedIntersection {
    static func leftBiasedIntersection() -> Generator<LeftBiasedIntersection, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4)
            .map { LeftBiasedIntersection(Set($0)) }
    }
}

extension Gen where Value == BuggySymmetricDifference {
    /// Generator for `BuggySymmetricDifference`. The element range produces
    /// occasional disjoint pairs and occasional overlapping pairs — both are
    /// needed to expose every law the bug violates (`x △ x` exercises the
    /// idempotent case, `x △ ∅` requires non-empty `x`, the definition law
    /// fires on partial overlap).
    static func buggySymmetricDifference() -> Generator<BuggySymmetricDifference, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4)
            .map { BuggySymmetricDifference(Set($0)) }
    }
}
