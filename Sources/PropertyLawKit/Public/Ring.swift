/// A ring with unity — an additive abelian group `(add, zero, negate)`
/// together with a multiplicative monoid `(multiply, one)`, linked by
/// left- and right-distributivity.
///
/// Conformance asserts, for all values `a`, `b`, `c` of `Self`:
/// - **Additive abelian group:** `add` is associative and commutative,
///   `zero` is a two-sided identity, and `negate(a)` is a two-sided
///   additive inverse.
/// - **Multiplicative monoid:** `multiply` is associative and `one` is a
///   two-sided multiplicative identity.
/// - **Distributivity:** `multiply(a, add(b, c)) == add(multiply(a, b), multiply(a, c))`
///   and the right-hand mirror.
///
/// The kit verifies all eleven laws via `checkRingPropertyLaws(...)`.
///
/// ## Standalone — refines nothing in the kit's algebraic DAG
///
/// Unlike `Semigroup` → `Monoid` → `CommutativeMonoid` → `{Group, Semilattice}`,
/// which all share a single `combine(_:_:)`, `Ring` is the kit's first
/// **two-operation** protocol. A ring's additive structure *is* an abelian
/// group and its multiplicative structure *is* a monoid, but binding the
/// chain's `combine` to one of `add` / `multiply` would (a) leave the other
/// operation lawless and (b) collide with any other single-op conformance
/// the type declares. So `Ring` declares its own operations and subsumes
/// nothing; nothing subsumes it. A type that is both `Ring` and (via a
/// different operation) `Monoid` surfaces both checks — they are genuinely
/// different claims. See `KnownProtocol.subsumedProtocols` and the
/// `docs/Protocols/v1.10 plan.md` "Why standalone" section.
///
/// ## Conformance shape
///
/// ```swift
/// struct IntMod5: Ring, Equatable {            // integers mod 5
///     let value: Int                       // 0...4
///     static let zero = IntMod5(value: 0)
///     static let one  = IntMod5(value: 1)
///     static func add(_ lhs: IntMod5, _ rhs: IntMod5) -> IntMod5 {
///         IntMod5(value: (lhs.value + rhs.value) % 5)
///     }
///     static func multiply(_ lhs: IntMod5, _ rhs: IntMod5) -> IntMod5 {
///         IntMod5(value: (lhs.value * rhs.value) % 5)
///     }
///     static func negate(_ v: IntMod5) -> IntMod5 {
///         IntMod5(value: (5 - v.value) % 5)
///     }
/// }
/// ```
///
/// `Equatable` is required to *check* the laws but not to *declare* the
/// conformance — same posture as `Semigroup`, `Monoid`, `Group`, and
/// `Semilattice`.
///
/// ## Why kit-defined
///
/// Stdlib's `Numeric` / `BinaryInteger` already get ring-shaped coverage
/// (the kit tests additive associativity / commutativity, distributivity,
/// and zero-annihilation on them via `+` / `*`). `Ring` is for carriers
/// whose ring operations are named something other than `+` / `*` —
/// modular arithmetic, square matrices, polynomials, dual numbers, Gaussian
/// integers, boolean rings. SwiftInferProperties already *infers* ring
/// structure but had no kit protocol to suggest conforming to; v1.10 closes
/// that loop (the last algebraic structure the inference engine speaks).
///
/// ## With unity, not a rng
///
/// `one` is required and the two multiply-identity laws are checked. Rngs
/// (rings without a multiplicative identity) are rare in idiomatic Swift;
/// requiring `one` matches the stdlib `Numeric` baseline and buys two laws
/// for almost no cost. A future `Rng` (multiply as a bare `Semigroup`) can
/// be added if a real carrier demands it.
public protocol Ring {
    /// The additive identity. `add(.zero, a) == a == add(a, .zero)`.
    static var zero: Self { get }

    /// The multiplicative identity. `multiply(.one, a) == a == multiply(a, .one)`.
    static var one: Self { get }

    /// The additive operation. Associative and commutative; `.zero` is its
    /// two-sided identity.
    static func add(_ lhs: Self, _ rhs: Self) -> Self

    /// The multiplicative operation. Associative; `.one` is its two-sided
    /// identity. Distributes over `add` on both sides. Not assumed commutative.
    static func multiply(_ lhs: Self, _ rhs: Self) -> Self

    /// The additive inverse. `add(negate(a), a) == .zero == add(a, negate(a))`.
    static func negate(_ value: Self) -> Self
}
