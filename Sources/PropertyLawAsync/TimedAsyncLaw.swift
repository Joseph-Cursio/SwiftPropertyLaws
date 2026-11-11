import PropertyLawKit

/// Phase 4 of the collections/async workplan — the virtual-time laws.
///
/// Time-parameterized combinators (`debounce` here; `throttle` when its API
/// stabilizes upstream) are nondeterministic against wall clocks but fully
/// deterministic against a ``VirtualClock`` run by ``runInVirtualTime(horizon:_:)``:
/// virtual time advances only when every task in the pipeline is blocked,
/// which is the whole trick. The generated carrier is again the source
/// array; per-element *gaps* and the debounce *interval* are derived
/// deterministically from position and count, so a seeded run replays
/// exactly.
///
/// **These laws first ran on swift-clocks' `TestClock`, and hung.** Its
/// `advance` cannot see when the tasks under test have settled, so it
/// yields a fixed number of times — about a millisecond of wall time — and
/// moves on. A sleeper that reached `clock.sleep` after that registered
/// against the advanced `now` and was never woken: measured, a source that
/// spent 1 ms on the CPU before each sleep hung every time, which is what
/// a loaded machine does to it. The scheduler drains its own queue instead,
/// so "settled" is a fact rather than a wait.
///
/// - `debounceOutputIsSubsequenceOfInput` — debounce may drop, never
///   invent or reorder: output is a (not necessarily contiguous)
///   subsequence of input.
/// - `debounceEmitsFinalElement` — the last input element always surfaces
///   once quiescence passes (non-empty input).
/// - `debounceIsDeterministicUnderTestClock` — two runs over fresh virtual
///   clocks produce identical output. This is the load-bearing law for the
///   workplan's effect story: *async + injected clock ⇒ deterministic*, the
///   refinement SwiftEffectInference's annotation route will name — and the
///   `TestClock` hang is the evidence that the injected clock is not enough
///   on its own: the scheduler has to know when the tasks are quiet. The
///   name predates ``VirtualClock`` and is kept because it is public API and
///   an emitted law string.
/// - `cancellationCeasesEmission` — cancelling the consuming task stops
///   the pipeline promptly (cancellation propagates through
///   `clock.sleep`), and everything observed before the cancel is a
///   prefix of the source. "Promptly" means *no virtual time passes*
///   between the cancel and the consumer finishing.
public enum TimedAsyncLaw: String, Sendable, Hashable, CaseIterable {
    case debounceOutputIsSubsequenceOfInput
    case debounceEmitsFinalElement
    case debounceIsDeterministicUnderTestClock
    case cancellationCeasesEmission
}

public extension LawIdentifier {
    /// Names one of the `TimedAsyncSequence` laws, for a `LawSuppression`.
    static func timedAsync(_ law: TimedAsyncLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "TimedAsyncSequence", lawName: law.rawValue)
    }
}
