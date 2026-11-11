/// v2.3.0 — declares "at most N of these flags / fields are
/// simultaneously non-empty" (PRD §5.4). SwiftInferProperties' M5
/// Cardinality template detector triggers conformance proposals
/// when ≥ 2 Bool / Optional fields with stem-matching names sit
/// in the State. Conformer's `invariantHolds` returns true when
/// the cardinality bound is respected.
public protocol CardinalityInvariant: InteractionInvariant {}

/// v2.3.0 — declares "every selected ID refers to an extant entity
/// in the corresponding collection" (PRD §5.5). M6 Referential
/// Integrity template detector triggers proposals when an Optional
/// whose name starts with `selected` sits alongside an array literal
/// `[T]` where `T: Identifiable`. Conformer's `invariantHolds`
/// returns true when the selected ID is nil or present in the
/// collection's id set.
public protocol ReferentialIntegrityInvariant: InteractionInvariant {}

/// v2.3.0 — declares "Bool flag iff Optional is non-nil" (PRD §5.6).
/// M7 Biconditional template detector triggers proposals when a
/// Bool field with a loading-shape name sits alongside any Optional
/// field. Conformer's `invariantHolds` returns true when the two
/// projected sides agree.
public protocol BiconditionalInvariant: InteractionInvariant {}

/// v2.3.0 — declares "a stored aggregate equals a derived recompute"
/// (PRD §5.3). M4 Conservation template detector triggers proposals
/// when a stored count-shaped field sits alongside an array whose
/// `.count` should agree. Conformer's `invariantHolds` returns true
/// when the stored and derived values agree.
public protocol ConservationInvariant: InteractionInvariant {}

/// v2.3.0 — declares "applying a from `idempotentActions` twice
/// equals applying it once" (PRD §5.2). M4 Idempotence template
/// detector triggers proposals when an Action enum case has a
/// curated idempotent name (`.refresh` / `.reset` / etc.).
///
/// Unlike the other four families, ActionIdempotence's law isn't a
/// state-level predicate — it's an action-application property. The
/// kit's harness keys on `idempotentActions` and checks
/// `reducer(reducer(s, a), a) == reducer(s, a)` for each. The
/// inherited `invariantHolds(in:)` defaults to `true` so conformers
/// don't have to provide a trivial implementation.
public protocol ActionIdempotenceInvariant: InteractionInvariant
where Self.State: Equatable {
    associatedtype Action: Hashable

    static var idempotentActions: Set<Action> { get }
}

/// v2.3.0 — root protocol for SwiftInferProperties v2.0's
/// **InteractionInvariantBridge** (PRD §9). Conformance declares a
/// state-level boolean predicate that an interaction-bearing reducer
/// is expected to preserve after every action it processes.
///
/// **The conformer is NOT the reducer.** Per PRD §9.2, the verify
/// harness takes the reducer as a closure parameter, so a single
/// invariant-bearing type doesn't need to *be* the reducer. Pattern:
/// the user writes a stub type that conforms to one of the five
/// family-specific sub-protocols (Cardinality / RefInt / etc.) and
/// implements `invariantHolds(in:)`; the harness drives the actual
/// reducer.
///
/// ## Conformance shape
///
/// ```swift
/// struct InboxCardinality: CardinalityInvariant {
///     static func invariantHolds(in state: Inbox.State) -> Bool {
///         (state.isShowingSheet ? 1 : 0)
///             + (state.isShowingAlert ? 1 : 0) <= 1
///     }
/// }
/// ```
///
/// ## Why kit-defined
///
/// SwiftInferProperties' M9 RefactorBridge (v1's equivalent: M8 in
/// SwiftPropertyLaws v1.9) promotes ≥ 3 Strong-tier interaction
/// invariants on the same reducer into a Bridge proposal — the user
/// conforms a stub type to each family-specific sub-protocol, and
/// the kit's discovery plugin runs the predicate check on every CI
/// invocation thereafter. Pre-v2.3.0 the protocols didn't exist;
/// the Bridge had no kit-side surface to propose.
///
/// ## Sub-protocols
///
/// The five family sub-protocols are **mutually independent** — no
/// hierarchy. PRD §9.4 documents that ≥ 2 firing simultaneously on
/// the same reducer surface as peer proposals, not nested choices.
/// `ActionIdempotenceInvariant` carries an additional Action
/// associatedtype + idempotent-action set; the other four refine
/// without adding requirements.
public protocol InteractionInvariant {
    /// The reducer state the invariant constrains.
    associatedtype State
    /// Whether `state` satisfies the invariant. The harness checks it after every step of an action sequence.
    static func invariantHolds(in state: State) -> Bool
}

public extension ActionIdempotenceInvariant {
    /// Always `true`: an action-idempotence invariant constrains actions, not states.
    static func invariantHolds(in _: State) -> Bool { true }
}
