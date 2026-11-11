/// Transformation-algebra laws over `Sequence` values (Phase 2 of the
/// collections/async workplan) — the higher-order counterpart to the
/// conformance families: instead of checking what a *type* promises, these
/// check what the stdlib's transformation methods promise over that type.
///
/// Four closure-free Strict-tier laws (the closure-parameterized laws —
/// map fusion, map/filter commutation, lazy-vs-eager — ship separately and
/// take caller-supplied functions):
///
/// - `sortedIdempotence` — `x.sorted().sorted() == x.sorted()`
/// - `sortedIsNonDecreasing` — no adjacent pair of `x.sorted()` is
///   out of order
/// - `sortedPreservesCount` — sorting neither drops nor invents elements
/// - `reversedInvolution` — reversing twice restores the original element
///   order (the *value* transform; distinct from
///   `BidirectionalCollection.reverseTraversalConsistency`, which checks
///   index walking)
///
/// **Multi-pass assumption.** Each property iterates its sample more than
/// once, so carriers must be multi-pass (every `Collection` is). Don't run
/// this family over single-pass sequences.
///
/// **No planted violator, deliberately.** `sorted()`/`reversed()` are
/// protocol-extension methods — a conforming type can't override them, so
/// there is no substitutable "buggy conformance" to plant (the M3
/// collections families note the same gap for concrete types). What these
/// laws *can* catch is a broken `Comparable` element corrupting `sorted()`
/// — but a violator's broken `<` would corrupt the law's own oracle
/// identically, so detection is not guaranteed; the family's evidence base
/// is upstream archaeology (the swift-collections Pass 3 precedent), not
/// the planted-bug gate.
public enum TransformationLaw: String, Sendable, Hashable, CaseIterable {
    case sortedIdempotence
    case sortedIsNonDecreasing
    case sortedPreservesCount
    case reversedInvolution
    // Parameterized half — see TransformationFunctionLaws.swift.
    case mapFusion
    case mapFilterCommutation
    case lazyMapEquivalence
    case lazyFilterEquivalence
}

public extension LawIdentifier {
    /// Names one of the `Transformation` laws, for a `LawSuppression`.
    static func transformation(_ law: TransformationLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Transformation", lawName: law.rawValue)
    }
}
