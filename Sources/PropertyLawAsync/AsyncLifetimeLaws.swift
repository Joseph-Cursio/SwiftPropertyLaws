import PropertyBased
import PropertyLawKit

// MARK: - Trials

/// The time a lifetime trial allows the operator per step: per element, and
/// once more for the source's ending. The source's own gaps come on top. Also
/// how long a failing source waits after its last element, and how long the
/// consumer pauses outside `next()`. Virtual, so it costs nothing; an operator
/// whose own delays are longer, or whose output outlives its source, is outside
/// what these laws can judge, and is reported as a hang.
let lifetimeSlack: Swift.Duration = .milliseconds(200)

/// `steps` slacks: the operator's allowance for that many steps.
func allowance(steps: Int) -> Swift.Duration {
    lifetimeSlack * steps
}

/// How many elements the laws read from an operator before giving up on it
/// ending. An operator may emit far more than it receives — `flatMap`, or a
/// `merge` with a long partner — and reading is cheap in virtual time, so the
/// cap only has to stop an operator that emits synchronously forever; one that
/// emits on the clock forever passes the horizon first.
let lifetimeEmissionCap = 10_000

/// The reason given when an operator passes ``lifetimeEmissionCap``.
private func passedTheCap(_ when: String) -> String {
    "the operator emitted more than \(lifetimeEmissionCap) elements \(when), the law's cap; an operator that "
        + "legitimately emits more is out of its scope"
}

/// Run one trial in virtual time. A run that deadlocks or would pass its
/// horizon is the operator hanging, and is reported as a violation that says
/// so; every other run error passes through. When `cancelled` was raised
/// first, the hang is a cancelled consumer whose `next()` never returned, an
/// operator fault rather than a limit of the law, and the message says so.
func runLifetimeTrial<Value: Sendable>(
    horizon: Swift.Duration,
    order: JobOrder,
    cancelled: ConsumerSignal? = nil,
    _ body: @escaping @Sendable (VirtualClock) async throws -> Value
) async throws -> Value {
    do {
        return try await runInVirtualTime(horizon: horizon, order: order, body)
    } catch let error as VirtualTimeError {
        switch error {
        case .deadlock, .horizonExceeded, .stepLimitExceeded:
            if cancelled?.isRaised == true {
                throw LifetimeLawViolation(
                    description: "hang: the consumer was cancelled and its next() never returned, so the operator "
                        + "ignores cancellation (\(error))"
                )
            }
            if case .stepLimitExceeded = error {
                // A livelock, not a wait on the clock, so the allowance per
                // step says nothing about it.
                throw LifetimeLawViolation(description: "hang: \(error)")
            }
            throw LifetimeLawViolation(
                description: "hang: \(error) (the law allows \(lifetimeSlack) per step; an operator that "
                    + "needs longer, or whose output outlives its source, is out of its scope)"
            )

        case .escaped:
            throw LifetimeLawViolation(
                description: "escaped: \(error); the lifetime laws need the operator's work to stay in virtual time"
            )

        case .hookUnavailable, .foreignHookInstalled, .nestedRun:
            throw error
        }
    }
}

func instant(_ offset: Swift.Duration) -> VirtualClock.Instant {
    VirtualClock.Instant(offset: offset)
}

/// The `releasesUpstreamWhenConsumerLeaves` property. Returns why it failed,
/// or `nil`.
///
/// The consumer calls `next()` once — taking an element, or seeing the
/// operator end — and drops its iterator. Once the run settles, every upstream
/// iterator the operator made must be gone. A consumer still waiting at the
/// deadline is cancelled so the trial can end, and the trial asserts nothing:
/// a consumer cancelled inside `next()` is the cancellation law's case.
func releasesUpstreamWhenConsumerLeaves<Element: Sendable, Output: AsyncSequence & Sendable>(
    of sample: [Element],
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output,
    order: JobOrder = .fifo
) async throws -> String? {
    let gaps = derivedGaps(count: sample.count)
    let deadline = gaps.reduce(Swift.Duration.zero, +) + allowance(steps: 1)
    let probe = LifetimeProbe()
    let cancelled = ConsumerSignal()
    let (left, seen) = try await runLifetimeTrial(
        horizon: deadline + lifetimeSlack, order: order, cancelled: cancelled
    ) { clock in
        let source = LifetimeProbeSource(
            clock: clock, gaps: gaps, elements: sample, ending: .park, tailGap: .zero, probe: probe
        )
        let returned = ConsumerSignal()
        let consumer = Task {
            var iterator = operation(source, LawClock(clock)).makeAsyncIterator()
            _ = try? await iterator.next()
            returned.raise()
        }
        try await clock.sleep(until: instant(deadline))
        let left = returned.isRaised
        cancelled.raise()
        consumer.cancel()
        await consumer.value
        await clock.settle()
        // Read before the run ends: tearing it down cancels every sleeper,
        // which would release a leaked upstream after the fact.
        return (left, probe.snapshot)
    }
    guard left, seen.released != seen.made else { return nil }
    return "the consumer called next() once and dropped its iterator, but \(seen.made - seen.released) "
        + "of the \(seen.made) upstream iterators the operator made were never released"
}

/// The `cancellationReachesUpstream` property. Returns why it failed, or
/// `nil`.
///
/// The consumer takes one element, waits outside `next()`, cancels itself and
/// calls `next()` again. That call must return, and once the run settles every
/// upstream iterator must be gone. A consumer that gets no element is
/// cancelled at the deadline, inside `next()`, and the same holds.
func cancellationReachesUpstream<Element: Sendable, Output: AsyncSequence & Sendable>(
    of sample: [Element],
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output,
    order: JobOrder = .fifo
) async throws -> String? {
    let gaps = derivedGaps(count: sample.count)
    let pause = gaps.reduce(Swift.Duration.zero, +) + allowance(steps: 1)
    let deadline = pause + lifetimeSlack
    let probe = LifetimeProbe()
    let cancelled = ConsumerSignal()
    let seen = try await runLifetimeTrial(
        horizon: deadline + lifetimeSlack, order: order, cancelled: cancelled
    ) { clock in
        let source = LifetimeProbeSource(
            clock: clock, gaps: gaps, elements: sample, ending: .park, tailGap: .zero, probe: probe
        )
        let consumer = Task {
            var iterator = operation(source, LawClock(clock)).makeAsyncIterator()
            _ = try? await iterator.next()
            try? await clock.sleep(until: instant(pause))
            cancelled.raise()
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? await iterator.next()
        }
        try await clock.sleep(until: instant(deadline))
        cancelled.raise()
        consumer.cancel()
        await consumer.value
        await clock.settle()
        // Read before the run ends, as in the release law.
        return probe.snapshot
    }
    guard seen.released != seen.made else { return nil }
    return "the consumer was cancelled between next() calls and called next() again, but "
        + "\(seen.made - seen.released) of the \(seen.made) upstream iterators the operator "
        + "made were never released"
}

/// The `failureReachesConsumerWithoutDemand` property. Returns why it failed,
/// or `nil`.
///
/// The consumer takes one element, then pauses outside `next()` past the
/// moment the source fails. Its later `next()` calls must end in the source's
/// failure, after whatever elements the operator still owes. An operator that
/// stops reading before the source fails — `prefix`, or `zip` with a shorter
/// partner — owes no failure, and passes.
func failureReachesConsumerWithoutDemand<Element: Sendable, Output: AsyncSequence & Sendable>(
    of sample: [Element],
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output,
    order: JobOrder = .fifo
) async throws -> String? {
    let gaps = derivedGaps(count: sample.count)
    let elementsEnd = gaps.reduce(Swift.Duration.zero, +)
    let failsAt = elementsEnd + lifetimeSlack
    let pause = failsAt + lifetimeSlack
    // An operator that reads its source ahead sees the failure at `failsAt`.
    // One that reads only on demand, as identity does, starts the remaining
    // gaps and the tail gap only after the pause, so the horizon covers both,
    // with an allowance per step.
    let horizon = pause + elementsEnd + lifetimeSlack + allowance(steps: sample.count + 2)
    let probe = LifetimeProbe()
    return try await runLifetimeTrial(horizon: horizon, order: order) { clock in
        let source = LifetimeProbeSource(
            clock: clock, gaps: gaps, elements: sample, ending: .fail, tailGap: lifetimeSlack, probe: probe
        )
        var iterator = operation(source, LawClock(clock)).makeAsyncIterator()
        func ended(_ error: Error?) -> String? {
            guard let error else {
                return probe.snapshot.failed
                    ? "the operator read the upstream failure and then finished without delivering it"
                    : nil
            }
            return error is LifetimeProbeFailure ? nil : "the operator threw \(error) instead of the upstream failure"
        }
        do {
            guard try await iterator.next() != nil else { return ended(nil) }
        } catch {
            return ended(error)
        }
        try await clock.sleep(until: instant(pause))
        for _ in 0 ..< lifetimeEmissionCap {
            do {
                guard try await iterator.next() != nil else { return ended(nil) }
            } catch {
                return ended(error)
            }
        }
        return passedTheCap("after the upstream failed")
    }
}

/// The `finishedStaysFinished` property. Returns why it failed, or `nil`.
///
/// Drain the operator until it returns `nil` or throws, then call `next()`
/// three more times: each must return `nil`.
func finishedStaysFinished<Element: Sendable, Output: AsyncSequence & Sendable>(
    of sample: [Element],
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output,
    order: JobOrder = .fifo
) async throws -> String? {
    let gaps = derivedGaps(count: sample.count)
    let ending: LifetimeProbeSource<Element>.Ending = sample.count.isMultiple(of: 2) ? .finish : .fail
    let horizon = gaps.reduce(Swift.Duration.zero, +) + allowance(steps: sample.count + 1)
    return try await runLifetimeTrial(horizon: horizon, order: order) { clock in
        let source = LifetimeProbeSource(
            clock: clock, gaps: gaps, elements: sample, ending: ending, tailGap: .zero, probe: LifetimeProbe()
        )
        var iterator = operation(source, LawClock(clock)).makeAsyncIterator()
        var emitted = 0
        draining: while true {
            do {
                guard try await iterator.next() != nil else { break draining }
            } catch {
                break draining
            }
            emitted += 1
            if emitted > lifetimeEmissionCap {
                return passedTheCap("without finishing")
            }
        }
        for call in 1 ... 3 {
            do {
                if let element = try await iterator.next() {
                    return "the operator emitted \(element) on call \(call) after it had finished"
                }
            } catch {
                return "the operator threw \(error) on call \(call) after it had finished"
            }
        }
        return nil
    }
}

// MARK: - Laws

/// Smaller samples to try when a sample fails: each with one element removed,
/// then each with two adjacent elements removed. Removing two keeps the
/// sample's parity, which `finishedStaysFinished` uses to choose how the
/// source ends, so a fault that shows with only one ending still shrinks. The
/// shrinker re-runs the law on each, so the reported counterexample, and its
/// reason, are the smallest one found.
private func shrinkingByRemoval<Element>(_ sample: [Element]) -> [[Element]] {
    let singles = sample.indices.map { index in
        var smaller = sample
        smaller.remove(at: index)
        return smaller
    }
    let pairs = sample.indices.dropLast().map { index in
        var smaller = sample
        smaller.removeSubrange(index ... index + 1)
        return smaller
    }
    return singles + pairs
}

private func checkLifetimeLaw<
    Element: Sendable,
    Shrinker: SendableSequenceType
>(
    _ law: AsyncLifetimeLaw,
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions,
    property: @escaping @Sendable ([Element], JobOrder) async throws -> String?
) async -> CheckResult {
    await runUnaryLaw(
        LawIdentifier.asyncLifetime(law).qualifiedName,
        source: scheduledSampler(generator, options: options),
        options: options,
        property: { input in
            if let reason = try await property(input.value, input.order) {
                throw LifetimeLawViolation(description: reason)
            }
            return true
        },
        formatCounterexample: { input, error in
            "source = \(input.value); " + (error?.message ?? "the law did not hold") + input.scheduleSuffix
        },
        // Same order of candidates as before; each keeps the seed that found
        // the failure, which under a seed is a different interleaving of a
        // smaller input but still a real failure, and replays the same.
        shrink: { input in shrinkingByRemoval(input.value).map(input.with) }
    )
}

/// Checks the lifetime laws for the `AsyncSequence` operator that `operation`
/// applies, with the given options.
///
/// Each trial hands `operation` a ``LifetimeProbeSource`` over a sample drawn
/// from `generator`, and a ``LawClock`` for an operator that needs one, and
/// consumes what it returns in virtual time. The laws then check what the
/// operator did to its upstream and its consumer once the consumer stopped
/// listening: see ``AsyncLifetimeLaw``. An operator that hangs fails rather
/// than blocking the test.
///
/// The laws assume the operator's output ends once its source ends, and that
/// it needs no more than 200 ms of the clock per element. An operator outside
/// that — one merged with a timer, or a throttle with a long interval — is
/// reported as hanging.
///
/// ```swift
/// try await checkAsyncLifetimePropertyLaws(
///     for: [Int].self,
///     using: Gen<Int>.int(in: 0 ... 9).array(of: 0 ... 8),
///     options: LawCheckOptions(budget: .standard)
/// ) { source, clock in
///     source.debounce(for: .milliseconds(10), clock: clock)
/// }
/// ```
///
/// The operator in the example is only an illustration: whether a given
/// release of it passes is what the laws are for.
///
/// - Parameters:
///   - generator: The source elements for each trial.
///   - options: The budget, enforcement and suppressions for the run.
///   - operation: Builds the operator under test on the given source and clock.
///     It runs once per trial, inside that trial's virtual time.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkAsyncLifetimePropertyLaws<
    Element: Sendable,
    Output: AsyncSequence & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: [Element].Type,
    using generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions,
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output
) async throws -> [CheckResult] {
    let suite = inVirtualTime(options)
    return try await runPropertyLawSuite(options: suite) {
        [
            await checkLifetimeLaw(.releasesUpstreamWhenConsumerLeaves, generator: generator, options: suite) {
                try await releasesUpstreamWhenConsumerLeaves(of: $0, applying: operation, order: $1)
            },
            await checkLifetimeLaw(.cancellationReachesUpstream, generator: generator, options: suite) {
                try await cancellationReachesUpstream(of: $0, applying: operation, order: $1)
            },
            await checkLifetimeLaw(.failureReachesConsumerWithoutDemand, generator: generator, options: suite) {
                try await failureReachesConsumerWithoutDemand(of: $0, applying: operation, order: $1)
            },
            await checkLifetimeLaw(.finishedStaysFinished, generator: generator, options: suite) {
                try await finishedStaysFinished(of: $0, applying: operation, order: $1)
            },
            await checkLifetimeLaw(
                .releasesUpstreamWhenSequenceDroppedLast, generator: generator, options: suite
            ) {
                try await releasesUpstreamWhenSequenceDroppedLast(of: $0, applying: operation, order: $1)
            },
        ]
    }
}

/// Checks the lifetime laws for the `AsyncSequence` operator that `operation`
/// applies, with the default options. See
/// ``checkAsyncLifetimePropertyLaws(for:using:options:applying:)``.
@discardableResult
public func checkAsyncLifetimePropertyLaws<
    Element: Sendable,
    Output: AsyncSequence & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: [Element].Type,
    using generator: Generator<[Element], Shrinker>,
    applying operation: @escaping @Sendable (LifetimeProbeSource<Element>, LawClock) -> Output
) async throws -> [CheckResult] {
    try await checkAsyncLifetimePropertyLaws(
        for: type, using: generator, options: LawCheckOptions(), applying: operation
    )
}
