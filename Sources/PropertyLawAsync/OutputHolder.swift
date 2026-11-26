import PropertyLawKit

/// Holds an operator's output, so the moment the last reference to it goes
/// is a statement in the law, not wherever the optimizer ends its lifetime.
private final class OutputHolder<Output>: @unchecked Sendable {
    var output: Output?

    init(_ output: Output) {
        self.output = output
    }
}

/// The `releasesUpstreamWhenSequenceDroppedLast` property. Returns why it
/// failed, or `nil`.
///
/// `releasesUpstreamWhenConsumerLeaves` drops the operator's output before the
/// first `next()`, so only the iterator is left to release. Here the consumer
/// holds the output as well, takes one element, then drops the iterator and,
/// in the same job, the output: `for try await x in shared { break }` and then
/// `shared = nil`. An operator that tears down in the sequence's `deinit` and
/// again when a consumer leaves must release its upstream whichever comes
/// first, and whatever its own tasks are doing in between. Once the run
/// settles, every upstream iterator must be gone. A consumer that got no
/// element by the deadline is cancelled, and the trial asserts nothing.
func releasesUpstreamWhenSequenceDroppedLast<Element: Sendable, Output: AsyncSequence & Sendable>(
    of sample: [Element],
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output,
    order: JobOrder = .fifo
) async throws -> String? {
    let gaps = derivedGaps(count: sample.count)
    let deadline = gaps.reduce(Swift.Duration.zero, +) + allowance(steps: 1)
    let probe = LifetimeProbe()
    let cancelled = ConsumerSignal()
    let horizon = deadline + lifetimeSlack
    let (dropped, seen) = try await runLifetimeTrial(horizon: horizon, order: order, cancelled: cancelled) { clock in
        let source = LifetimeProbeSource(
            clock: clock, gaps: gaps, elements: sample, ending: .park, tailGap: .zero, probe: probe
        )
        let droppedBoth = ConsumerSignal()
        let consumer = Task {
            let holder = OutputHolder(operation(source, LawClock(clock)))
            var iterator = holder.output?.makeAsyncIterator()
            // `try?` flattens: nil when next() ended, threw or had no iterator.
            let first = try? await iterator?.next()
            guard first != nil else { return }
            iterator = nil
            holder.output = nil
            droppedBoth.raise()
        }
        try await clock.sleep(until: instant(deadline))
        let dropped = droppedBoth.isRaised
        cancelled.raise()
        consumer.cancel()
        await consumer.value
        await clock.settle()
        // Read before the run ends, as the release law does.
        return (dropped, probe.snapshot)
    }
    guard dropped, seen.released != seen.made else { return nil }
    return "the consumer took one element, then dropped its iterator and then the sequence, but "
        + "\(seen.made - seen.released) of the \(seen.made) upstream iterators the operator made were "
        + "never released"
}
