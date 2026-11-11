import PropertyLawKit

/// Laws for `Heap` — the first model-based family in the kit (Phase 1 M3 of
/// the collections/async workplan). `Heap` sits outside the stdlib protocol
/// lattice (not `Sequence`), so instead of protocol-conformance laws it gets
/// oracle laws against the sorted-array model:
///
/// - `drainMinYieldsSortedAscending` — repeatedly `popMin()` until empty
///   yields exactly `unordered.sorted()`.
/// - `drainMaxYieldsSortedDescending` — repeatedly `popMax()` yields exactly
///   `unordered.sorted(by: >)`.
/// - `minMaxAreUnorderedBounds` — `min` / `max` agree with the model's
///   `min()` / `max()`.
/// - `insertDuplicateMinPopsEqual` — inserting a copy of the current
///   minimum, then `popMin()`, returns a value equal to it (vacuous on the
///   empty heap).
///
/// Unlike the protocol families these laws are stated over the concrete
/// `Heap<Element>` (there is no heap protocol to abstract over), so the
/// planted-violator self-test gate doesn't apply — the laws exercise
/// swift-collections itself, not substitutable user conformances.
public enum HeapLaw: String, Sendable, Hashable, CaseIterable {
    case drainMinYieldsSortedAscending
    case drainMaxYieldsSortedDescending
    case minMaxAreUnorderedBounds
    case insertDuplicateMinPopsEqual
}

public extension LawIdentifier {
    /// Names one of the `Heap` laws, for a `LawSuppression`.
    static func heap(_ law: HeapLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Heap", lawName: law.rawValue)
    }
}
