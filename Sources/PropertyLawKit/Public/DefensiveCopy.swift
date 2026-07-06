/// v3.7.0 — kit-defined protocol for **defensive-copy correctness**: the
/// reference-type companion to `ValueSemantic` (pbt-book Chapter 9 §9.3). A
/// class that vends a `copy()` / `clone()` claims that copy is *equal by value*
/// but a *distinct object*, and that mutating the copy does not affect the
/// source. Both halves are testable properties.
///
/// ## The two laws (`checkDefensiveCopyPropertyLaws`)
///
///   - **`copyIsDistinctInstance`** — `x.copyUnderTest() !== x`. Catches the
///     `copy()` that accidentally `return self`s (equal by `==`, but the same
///     object — §9.3.2's defensive-copy bug).
///   - **`copyIsIndependent`** — mutating `x.copyUnderTest()` must not affect
///     `x`. This is the `ValueSemantic` copy-mutate-compare law with the copy
///     operation being `copyUnderTest()` instead of a struct value-copy — it
///     catches a *shallow* copy that shares a mutable reference member.
///
/// ## Conformance shape
///
/// The conformer describes its mutation surface as a `CaseIterable` enum (as
/// `ValueSemantic` does), plus a deterministic probe and the copy method under
/// test. `apply` takes the target by reference (a class mutates in place — no
/// `inout`):
///
/// ```swift
/// final class Buffer: DefensiveCopy {
///     private var bytes: [UInt8] = []
///     func appended(_ b: UInt8) { bytes.append(b) }
///     func copy() -> Buffer { let c = Buffer(); c.bytes = bytes; return c }
///
///     static func == (lhs: Buffer, rhs: Buffer) -> Bool { lhs.bytes == rhs.bytes }
///     static func makeProbe() -> Buffer { Buffer() }
///     func copyUnderTest() -> Buffer { copy() }
///     enum Mutation: CaseIterable, Sendable { case appendOne }
///     static func apply(_ mutation: Mutation, to target: Buffer) {
///         switch mutation { case .appendOne: target.appended(1) }
///     }
/// }
/// ```
///
/// `makeProbe()` is called repeatedly; **each call must return an equal-valued,
/// independently-constructed instance** (two probes must be `==` and must not
/// share reference-backed storage) — the same contract as `ValueSemantic`.
public protocol DefensiveCopy: AnyObject, Equatable {

    /// The type's mutation surface — one case per mutating operation. Drives the
    /// copy through reachable states + exercises copy-independence.
    associatedtype Mutation: CaseIterable & Sendable

    /// A deterministic base instance (equal-valued + independently constructed).
    static func makeProbe() -> Self

    /// The copy method under test — calls the type's real `copy()` / `clone()`.
    func copyUnderTest() -> Self

    /// Apply one mutation to `target` in place. A class mutates by reference, so
    /// `target` is passed without `inout`.
    static func apply(_ mutation: Mutation, to target: Self)
}
