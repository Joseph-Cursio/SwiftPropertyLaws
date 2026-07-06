/// v3.3.0 — kit-defined protocol for **value semantics**: mutating one
/// instance of `Self` must never be observable through any other instance.
/// The load-bearing slice of SwiftInferProperties' ValueSemantic build plan
/// (`SwiftInferProperties/docs/valuesemantic-build-plan.md`); conceptual
/// source is the pbt-book Chapter 9, "Value semantics, COW and identity."
///
/// ## The property
///
/// For every mutating operation `m` on `Self` and every instance `a`:
///
/// ```text
/// var b = a; apply(m, to: &b);   a is unchanged
/// ```
///
/// A `struct` gets this for free only if *every* stored property does too.
/// The moment it holds a class reference, an `NSMutableArray`, or a closure
/// capturing mutable state, a "value" can leak shared storage through that
/// escape hatch — and the copy-mutate-compare law fails (Chapter 9 §9.1.3).
///
/// ## Conformance shape
///
/// The conformer describes its own **mutation surface** as a `CaseIterable`
/// enum (the mutating methods a copy-independence bug could leak through) and
/// how to apply each case, plus a deterministic base instance:
///
/// ```swift
/// struct Buffer: ValueSemantic {
///     private final class Storage { var bytes: [UInt8] = [] }
///     private var storage = Storage()
///     var bytes: [UInt8] { storage.bytes }
///     mutating func append(_ byte: UInt8) {
///         if !isKnownUniquelyReferenced(&storage) { storage = storage.clone() }
///         storage.bytes.append(byte)
///     }
///
///     static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
///     static func makeProbe() -> Self { Buffer() }
///     enum Mutation: CaseIterable, Sendable { case appendOne }
///     static func apply(_ mutation: Mutation, to target: inout Self) {
///         switch mutation { case .appendOne: target.append(1) }
///     }
/// }
/// ```
///
/// ## Why the mutation surface is a `CaseIterable` enum
///
/// Reusing `ActionSequenceFactory` (v2.2.0) — the same command-sequence
/// machinery the InteractionInvariant family uses — the harness samples a
/// *script* of mutations and applies it to a copy. Modelling the surface as a
/// `CaseIterable` enum (rather than a list of closures) mirrors the
/// InteractionInvariant `Action` shape, so the same generation + shrinking
/// substrate carries value-semantics verification with no new primitive.
///
/// ## `makeProbe()` contract
///
/// `makeProbe()` is called multiple times per check; **each call must return
/// an equal-valued but independently-constructed instance** (two probes must
/// be `==` and must not share reference-backed storage). The harness compares
/// a mutated copy's origin against a pristine twin, so a non-deterministic
/// `makeProbe()` surfaces as a (correctly reported) law failure on the empty
/// script.
public protocol ValueSemantic: Equatable {

    /// The type's mutation surface — one case per mutating operation a
    /// copy-independence bug could leak through. `CaseIterable` so the harness
    /// can sample mutation scripts via `ActionSequenceFactory`.
    associatedtype Mutation: CaseIterable & Sendable

    /// A deterministic base instance. Called repeatedly; every call must
    /// return an equal-valued, independently-constructed instance that shares
    /// no reference-backed storage with any other probe.
    static func makeProbe() -> Self

    /// Apply one mutation to `target` in place. Drives the type's mutation
    /// surface during the copy-mutate-compare check.
    static func apply(_ mutation: Mutation, to target: inout Self)
}
