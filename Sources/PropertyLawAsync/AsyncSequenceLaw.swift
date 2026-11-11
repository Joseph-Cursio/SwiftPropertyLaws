import PropertyLawKit

/// Async-tier-1 laws for swift-async-algorithms (Phase 3 of the
/// collections/async workplan) — the clock-free subset.
///
/// **The central pattern is sync-model equivalence**: a deterministic
/// single-source combinator, fed a finite source, must agree with its
/// synchronous counterpart on the collected elements. The generated carrier
/// is the *source array*; each law lifts it with `.async`
/// (`AsyncSyncSequence`) and compares the collected pipeline against a
/// plain-array model. This is the Chapter 3/19 oracle pattern applied to
/// async — no virtual time, no ordering theory. Clock-parameterized
/// combinators (`debounce`, `throttle`, …) are Phase 4.
///
/// Laws (`chunk` size, `interspersed` separator, and the optional-injection
/// pattern for `compacted` are all derived deterministically from the
/// sample, keeping the seed → outcome chain intact):
///
/// - `chunksMatchSyncModel` / `chunksConcatenationRestoresSource`
/// - `adjacentPairsMatchSyncModel`
/// - `removeDuplicatesMatchesSyncModel` (consecutive-duplicate semantics)
/// - `interspersedMatchesSyncModel`
/// - `compactedMatchesCompactMap`
/// - `mergePreservesElementMultiset` — `merge` interleaving is
///   scheduler-dependent, so the law compares *multisets* (sorted
///   collections), the coarser equivalence under which merge is
///   deterministic. The order-insensitivity is the point: it is the same
///   "commutative under which equality?" lesson as OrderPreservationLaws.
/// - `zipMatchesSyncZip` — zip *is* order-deterministic; pairs and length
///   (`min` of the inputs) match `Swift.zip` exactly.
/// - `asyncIteratorStaysExhausted` — after `next()` returns `nil`, it keeps
///   returning `nil` (the AsyncIteratorProtocol mirror of the sync
///   `terminationStability` law).
public enum AsyncSequenceLaw: String, Sendable, Hashable, CaseIterable {
    case chunksMatchSyncModel
    case chunksConcatenationRestoresSource
    case adjacentPairsMatchSyncModel
    case removeDuplicatesMatchesSyncModel
    case interspersedMatchesSyncModel
    case compactedMatchesCompactMap
    case mergePreservesElementMultiset
    case zipMatchesSyncZip
    case asyncIteratorStaysExhausted
}

public extension LawIdentifier {
    /// Names one of the `AsyncSequence` laws, for a `LawSuppression`.
    static func asyncSequence(_ law: AsyncSequenceLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "AsyncSequence", lawName: law.rawValue)
    }
}
