import Foundation
import PropertyBased

/// Violates Hashable.equalityConsistency: `==` always returns true (so any two
/// instances are equal) but `hash(into:)` derives from a stored UUID — every
/// instance hashes differently. This guarantees the equality-consistency law
/// is hit on the very first trial that pulls two distinct values.
struct EqualButDifferentHash: Hashable, Sendable, CustomStringConvertible {
    let id: UUID

    init() { self.id = UUID() }

    static func == (_: Self, _: Self) -> Bool {
        true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var description: String { "EBH(\(id.uuidString.prefix(4)))" }
}

/// Violates Hashable.distribution (Heuristic tier): every value hashes to the
/// same final integer because `hash(into:)` only ever combines a constant.
/// equalityConsistency holds (equal `value`s hash equal); stability holds
/// (deterministic). Used to verify the distribution-violation reporting path
/// and the `TrialRunner.runAggregate` violation-packaging branch.
struct DegenerateHasher: Hashable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(0) // every instance hashes identically
    }

    var description: String { "DH(\(value))" }
}

/// A Hashable type whose Equatable witness violates reflexivity. Used to
/// exercise the inherited-Equatable-violation re-collection branch in
/// `checkHashablePropertyLaws(..., laws: .all)`.
struct ReflexivityBreakingHashable: Hashable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (_: Self, _: Self) -> Bool {
        false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
    }

    var description: String { "RBH(\(value))" }
}

/// Violates Hashable.stabilityWithinProcess (Conventional tier) ONLY.
///
/// `==` deliberately returns `false` so the `equalityConsistency` law (Strict)
/// is vacuously satisfied — no two values are ever equal, so the implication
/// "x == y → x.hashValue == y.hashValue" is never tested. That isolates the
/// stability violation, which is what we want to verify the .strict
/// enforcement-mode escalation against.
struct UnstableHasher: Hashable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (_: Self, _: Self) -> Bool {
        false
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        hasher.combine(UUID()) // fresh per call → unstable across reads
    }

    var description: String { "U(\(value))" }
}

extension Gen where Value == EqualButDifferentHash {
    static func equalButDifferentHash() -> Generator<EqualButDifferentHash, some SendableSequenceType> {
        Gen<Int>.int(in: 0...1_000_000).map { _ in EqualButDifferentHash() }
    }
}

extension Gen where Value == UnstableHasher {
    static func unstableHasher() -> Generator<UnstableHasher, some SendableSequenceType> {
        Gen<Int>.int(in: 0...100).map { UnstableHasher(value: $0) }
    }
}

extension Gen where Value == DegenerateHasher {
    static func degenerate() -> Generator<DegenerateHasher, some SendableSequenceType> {
        Gen<Int>.int(in: 0...1_000).map { DegenerateHasher(value: $0) }
    }
}

extension Gen where Value == ReflexivityBreakingHashable {
    static func reflexivityBreaking() -> Generator<ReflexivityBreakingHashable, some SendableSequenceType> {
        Gen<Int>.int(in: 0...50).map { ReflexivityBreakingHashable(value: $0) }
    }
}
