import PropertyBased
import PropertyLawKit

/// Violates `Semigroup.combineAssociativity`. `combine` floor-divides by 2
/// when both operands are non-zero, mirroring the trick `NonAssociativeAddition`
/// uses for `AdditiveArithmetic` — the regrouping commutes for additive
/// triples but not for the non-zero short-circuit, so `(x • y) • z` and
/// `x • (y • z)` diverge for many input triples.
struct NonAssociativeCombine: Semigroup, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        let raw = lhs.value + rhs.value
        if lhs.value != 0, rhs.value != 0 {
            return Self(value: raw / 2)
        }
        return Self(value: raw)
    }

    var description: String { "NAC(\(value))" }
}

extension Gen where Value == NonAssociativeCombine {
    static func nonAssociativeCombine() -> Generator<NonAssociativeCombine, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { NonAssociativeCombine(value: $0) }
    }
}
