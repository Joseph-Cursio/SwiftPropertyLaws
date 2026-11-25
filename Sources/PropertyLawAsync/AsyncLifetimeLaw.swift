import PropertyLawKit

/// The lifetime laws: what an `AsyncSequence` operator owes its upstream and
/// its consumer once the consumer stops listening.
///
/// Unlike ``TimedAsyncLaw``, three of whose four laws check `debounce` itself,
/// these take the operator under test as a closure, so they apply to any operator and can be
/// shown to fail on a planted violator. Each trial feeds the operator a
/// ``LifetimeProbeSource`` on a ``LawClock`` and runs in virtual time, so a
/// hang is reported, not awaited: a trial that can only go on by passing its
/// horizon, or in which every task is blocked and nothing sleeps, fails with
/// a counterexample that says "hang".
///
/// - `releasesUpstreamWhenConsumerLeaves` — the consumer calls `next()` once
///   and drops the iterator, as a `break` out of `for try await` does; once
///   the run settles, every upstream iterator the operator made is released.
///   The source parks after its elements, so an operator that keeps a task
///   waiting on it leaks it. A consumer still waiting at the deadline is
///   cancelled and that trial asserts nothing here: it is the next law's case.
/// - `cancellationReachesUpstream` — the consumer takes one element, is
///   cancelled while *outside* `next()`, then calls `next()` again: that call
///   returns, and once the run settles every upstream iterator is released.
/// - `failureReachesConsumerWithoutDemand` — the consumer pauses outside
///   `next()` past the moment the upstream fails; its later `next()` calls end
///   in that failure (after any elements the operator still owes), rather than
///   finishing as if nothing happened. For an operator that reads its upstream
///   ahead, the failure arrives with no demand outstanding; for one that reads
///   on demand, it arrives during a later `next()`. An operator that stops
///   reading before the upstream fails owes no failure.
/// - `finishedStaysFinished` — once the operator's iterator has returned
///   `nil` or thrown, every further `next()` returns `nil`. The source
///   finishes for an even number of elements and fails for an odd one, so
///   both endings are covered.
///
/// The laws assume the operator's output ends once its source ends and that it
/// needs at most 200 ms of the clock per element; see
/// ``checkAsyncLifetimePropertyLaws(for:using:options:applying:)``.
public enum AsyncLifetimeLaw: String, Sendable, Hashable, CaseIterable {
    case releasesUpstreamWhenConsumerLeaves
    case cancellationReachesUpstream
    case failureReachesConsumerWithoutDemand
    case finishedStaysFinished
}

public extension LawIdentifier {
    /// Names one of the `AsyncLifetime` laws, for a `LawSuppression`.
    static func asyncLifetime(_ law: AsyncLifetimeLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "AsyncLifetime", lawName: law.rawValue)
    }
}
