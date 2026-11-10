import PropertyBased
import PropertyLawKit

/// Violates `Monoid.combineLeftIdentity`. `combine(.identity, x)` returns
/// `Bumped(x.value + 1)` instead of `x`. The right-identity case still
/// holds, and associativity holds because `combine` is otherwise
/// commutative+associative integer addition.
struct BadLeftIdentity: Monoid, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = Self(value: 0)

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        if lhs.value == 0, rhs.value != 0 {
            return Self(value: rhs.value + 1)
        }
        return Self(value: lhs.value + rhs.value)
    }

    var description: String { "BLI(\(value))" }
}

/// Violates `Monoid.combineRightIdentity`. Mirror image of `BadLeftIdentity`
/// — the right-identity short-circuit bumps by 1 instead of returning
/// `lhs`. Left identity still holds.
struct BadRightIdentity: Monoid, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = Self(value: 0)

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        if rhs.value == 0, lhs.value != 0 {
            return Self(value: lhs.value + 1) // the bug: right identity bumps instead of returning lhs
        }
        return Self(value: lhs.value + rhs.value)
    }

    var description: String { "BRI(\(value))" }
}

extension Gen where Value == BadLeftIdentity {
    static func badLeftIdentity() -> Generator<BadLeftIdentity, some SendableSequenceType> {
        Gen<Int>.int(in: 1...50).map { BadLeftIdentity(value: $0) }
    }
}

extension Gen where Value == BadRightIdentity {
    static func badRightIdentity() -> Generator<BadRightIdentity, some SendableSequenceType> {
        Gen<Int>.int(in: 1...50).map { BadRightIdentity(value: $0) }
    }
}
