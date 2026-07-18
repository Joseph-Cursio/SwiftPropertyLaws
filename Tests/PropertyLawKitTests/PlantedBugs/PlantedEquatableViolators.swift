import PropertyBased

/// Each of these types deliberately violates one Equatable Strict law, so the
/// framework's self-test gate (PRD §8) can assert detection.

/// Violates symmetry by ordering the comparison: `==` reports `lhs.priority > rhs.priority`,
/// which is asymmetric for distinct priorities.
struct PriorityCompareEquatable: Equatable, Sendable, CustomStringConvertible {
    let priority: Int

    static func == (lhs: PriorityCompareEquatable, rhs: PriorityCompareEquatable) -> Bool {
        lhs.priority > rhs.priority
    }

    var description: String { "P(\(priority))" }
}

extension Gen where Value == PriorityCompareEquatable {
    static func priorityCompare() -> Generator<PriorityCompareEquatable, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20).map { PriorityCompareEquatable(priority: $0) }
    }
}

/// Violates *only* symmetry: `==` reports `lhs.rank >= rhs.rank`. Unlike
/// `PriorityCompareEquatable` (whose `>` also breaks reflexivity), `>=` is
/// reflexive (`a >= a`), transitive (so `a == b && b == c ⇒ a == c` holds), and
/// negation-consistent — leaving symmetry as the single broken law. This is the
/// violator that *isolates* the symmetry arm, so a symmetry regression can be
/// pinned to symmetry rather than caught incidentally by another law.
struct SymmetryOnlyEquatable: Equatable, Sendable, CustomStringConvertible {
    let rank: Int

    static func == (lhs: SymmetryOnlyEquatable, rhs: SymmetryOnlyEquatable) -> Bool {
        lhs.rank >= rhs.rank
    }

    var description: String { "S(\(rank))" }
}

extension Gen where Value == SymmetryOnlyEquatable {
    static func symmetryOnly() -> Generator<SymmetryOnlyEquatable, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20).map { SymmetryOnlyEquatable(rank: $0) }
    }
}

/// Violates transitivity via rounding: equality holds within ±1, but two values
/// that are each within 1 of each other can be more than 1 apart from each other.
struct RoundingEquatable: Equatable, Sendable, CustomStringConvertible {
    let raw: Int

    static func == (lhs: RoundingEquatable, rhs: RoundingEquatable) -> Bool {
        abs(lhs.raw - rhs.raw) <= 1
    }

    var description: String { "R(\(raw))" }
}

extension Gen where Value == RoundingEquatable {
    static func rounding() -> Generator<RoundingEquatable, some SendableSequenceType> {
        Gen<Int>.int(in: 0...3).map { RoundingEquatable(raw: $0) }
    }
}

// Note on Equatable.negationConsistency: this law is structurally unviolable
// in Swift. `!=` is implemented by Equatable as `!(lhs == rhs)` and dispatched
// through the protocol witness — overloading `!=` on a concrete type does not
// change generic call sites. The law check ships in `EquatableLaws.swift` as
// defensive documentation rather than as a bug-detection mechanism, and there
// is therefore no planted-bug entry for it.

/// Violates reflexivity: `==` returns false even for the same instance.
struct AntiReflexiveEquatable: Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (lhs: AntiReflexiveEquatable, rhs: AntiReflexiveEquatable) -> Bool {
        false
    }

    var description: String { "AR(\(value))" }
}

extension Gen where Value == AntiReflexiveEquatable {
    static func antiReflexive() -> Generator<AntiReflexiveEquatable, some SendableSequenceType> {
        Gen<Int>.int(in: 0...5).map { AntiReflexiveEquatable(value: $0) }
    }
}
