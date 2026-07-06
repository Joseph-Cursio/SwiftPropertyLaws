/// v3.8.0 — kit-defined protocol for **identity stability under mutation**
/// (pbt-book Chapter 9 §9.3.3). A `Hashable` reference type whose `==` /
/// `hashValue` is meant to be a stable identity must not change what it is
/// equal / identical to when the object is mutated. A class whose `==` or
/// `hash(into:)` reads a *mutable* (`var`) stored field breaks this: mutating
/// an instance already living in a `Set` / `Dictionary` moves its hash bucket
/// and silently corrupts the collection.
///
/// Distinct from the kit's Hashable-consistency law (`a == b ⇒ equal hashes`,
/// a static relation between two objects) — this is one object's hash / equality
/// being *invariant across mutation* (a temporal property).
///
/// ## The two laws (`checkStableIdentityPropertyLaws`)
///
///   - **`hashStableUnderMutation`** — `x.hashValue` is unchanged after driving
///     the mutation surface. A change means the hash reads mutable state.
///   - **`equalityStableUnderMutation`** — whether `x` equals an independent
///     twin is unchanged after mutating `x`. A flip means `==` reads mutable
///     state.
///
/// ## Conformance shape
///
/// A `CaseIterable` mutation surface (as the other families use), a
/// deterministic probe, and an `apply` that mutates in place (a class mutates
/// by reference — no `inout`):
///
/// ```swift
/// final class Node: StableIdentity {
///     let id: Int
///     var label: String = ""
///     init(id: Int) { self.id = id }
///     static func == (lhs: Node, rhs: Node) -> Bool { lhs.id == rhs.id }
///     func hash(into hasher: inout Hasher) { hasher.combine(id) }
///
///     static func makeProbe() -> Node { Node(id: 0) }
///     enum Mutation: CaseIterable, Sendable { case relabel }
///     static func apply(_ mutation: Mutation, to target: Node) {
///         switch mutation { case .relabel: target.label = "x" }
///     }
/// }
/// ```
public protocol StableIdentity: AnyObject, Hashable {

    /// The type's mutation surface — one case per mutating operation, used to
    /// probe whether any of them disturbs the identity.
    associatedtype Mutation: CaseIterable & Sendable

    /// A deterministic base instance (equal-valued across calls).
    static func makeProbe() -> Self

    /// Apply one mutation to `target` in place (a class mutates by reference).
    static func apply(_ mutation: Mutation, to target: Self)
}
