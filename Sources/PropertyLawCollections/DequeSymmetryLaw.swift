import PropertyLawKit

/// Laws for `Deque`'s double-ended surface (Phase 1 M3 of the
/// collections/async workplan). The protocol chains (M1) already cover
/// Deque-as-RangeReplaceableCollection; what they can't see is the front
/// end — `prepend`/`popFirst` have no protocol home, so they get mirror
/// laws of the append side plus an array-model agreement law:
///
/// - `prependPopFirstRoundTrips` — prepending a value then `popFirst()`
///   returns it and restores the original deque.
/// - `appendPopLastRoundTrips` — the back-end mirror.
/// - `arrayModelRoundTrip` — `Deque(Array(deque)) == deque`: a deque is
///   observationally its array model.
///
/// Stated over the concrete `Deque<Element>` (no double-ended protocol
/// exists to abstract over), so the planted-violator self-test gate doesn't
/// apply — these exercise swift-collections itself.
public enum DequeSymmetryLaw: String, Sendable, Hashable, CaseIterable {
    case prependPopFirstRoundTrips
    case appendPopLastRoundTrips
    case arrayModelRoundTrip
}

public extension LawIdentifier {
    /// Names one of the `Deque` laws, for a `LawSuppression`.
    static func dequeSymmetry(_ law: DequeSymmetryLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Deque", lawName: law.rawValue)
    }
}
