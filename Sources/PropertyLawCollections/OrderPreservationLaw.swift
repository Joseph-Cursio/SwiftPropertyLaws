import OrderedCollections
import PropertyBased
import PropertyLawKit

/// Laws for `OrderedSet`'s defining behavior — insertion-order preservation
/// (Phase 1 M3 of the collections/async workplan). `OrderedSet` deliberately
/// isn't `SetAlgebra` because its set operations are order-asymmetric; these
/// laws pin down exactly that asymmetry instead of pretending it away:
///
/// - `appendExistingPreservesOrder` — re-appending every element the set
///   already contains reports `inserted == false` each time and leaves the
///   set (including order) unchanged.
/// - `unionKeepsLeftOrderThenNovelRight` — `x.union(y)` is exactly `x`'s
///   elements in `x`'s order followed by `y`'s novel elements in `y`'s
///   order. This *is* the order-sensitivity of union, stated as a total
///   deterministic definition rather than an inequality.
/// - `unionIsMembershipCommutative` — under membership equality
///   (`Set(_:)` projection), union commutes after all.
///
/// The last two are a metamorphic pair: the same operation commutes under
/// the coarser equivalence and is order-defined under the finer one —
/// the "commutative under *which* equality?" lesson, executable.
public enum OrderPreservationLaw: String, Sendable, Hashable, CaseIterable {
    case appendExistingPreservesOrder
    case unionKeepsLeftOrderThenNovelRight
    case unionIsMembershipCommutative
}

public extension LawIdentifier {
    /// Names one of the `OrderedSet` laws, for a `LawSuppression`.
    static func orderPreservation(_ law: OrderPreservationLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "OrderedSet", lawName: law.rawValue)
    }
}
