/// A "same result" equivalence chosen for a law's *oracle*, kept separate from
/// the type's own `==`.
///
/// Equational laws (commutativity, associativity, …) compare the two sides of
/// an equation. That comparison needs an *equivalence relation*, but IEEE-754
/// `==` is not one — `NaN != NaN` breaks reflexivity, so a genuinely
/// commutative operation that returns `NaN` on both sides reports a spurious
/// counterexample (see book §8.1.4–8.1.5). `SameResult` lets a caller inject
/// the correct oracle without changing the type's `==`.
///
/// The default for exact carriers (`Int`, `BigInt`, …) is plain `==`: integers
/// have no `NaN`, so `==` is already a genuine equivalence and needs no
/// adjustment (their boundary case is *overflow*, handled in the generator's
/// domain, not the oracle).
public typealias SameResult<Value> = @Sendable (Value, Value) -> Bool

/// The `NaN`-reflexive equivalence for IEEE-754 floating-point carriers.
///
/// `(a.isNaN && b.isNaN) || a == b` — two `NaN`s count as the same result,
/// everything else falls back to exact `==`.
///
/// **No tolerance term, by design.** The only algebraic law this equivalence is
/// used to run over floats is *commutativity* of `+` and `*`, which is
/// **exact** in IEEE-754 (bit-for-bit, modulo `NaN`): `a + b` and `b + a`
/// produce the identical value, as do `a * b` and `b * a`. So exact `==` plus
/// `NaN`-reflexivity is provably sufficient and correct here — a tolerance term
/// would be unnecessary. It must *not* be used to smuggle in associativity or
/// distributivity: those fail by **unbounded** amounts under catastrophic
/// cancellation and no fixed tolerance rescues them, which is why the kit
/// excludes them over floating-point rather than toleranciing them.
///
/// Stdlib-only: no `swift-numerics` dependency, so it lives on the main
/// `PropertyLawKit` line. The `Complex<Double>` carrier's own `==` is already
/// `NaN`-reflexive (swift-numerics collapses every non-finite value to a single
/// "point at infinity"), so `Complex` needs no bespoke equivalence — it is the
/// *lossier* carrier, not a more authoritative one.
@Sendable
public func floatSameResult<Value: FloatingPoint>(_ first: Value, _ second: Value) -> Bool {
    (first.isNaN && second.isNaN) || first == second
}
