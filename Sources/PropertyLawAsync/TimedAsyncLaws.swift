import AsyncAlgorithms
import PropertyBased
import PropertyLawKit

// MARK: - Timed source

/// Position-derived gaps (1–25 ms) — mixed against the 10 ms debounce
/// interval so runs contain both coalesced and passing gaps.
func derivedGaps(count: Int) -> [Swift.Duration] {
    (0 ..< count).map { index in .milliseconds(index * 7 % 25 + 1) }
}

let debounceInterval: Swift.Duration = .milliseconds(10)

/// Run the sample through debounce in virtual time.
///
/// The horizon is the slack the laws allow for quiescence: the last element
/// arrives at the sum of the gaps and debounce owes it one interval later.
/// A pipeline that still needs a sleeper past two intervals has stopped
/// settling, and fails as `horizonExceeded` rather than running on.
func debouncedOutput<Element: Sendable>(of sample: [Element]) async throws -> [Element] {
    let gaps = derivedGaps(count: sample.count)
    let horizon = gaps.reduce(Swift.Duration.zero, +) + debounceInterval + debounceInterval
    return try await runInVirtualTime(horizon: horizon) { clock in
        try await collect(
            TimedSource(clock: clock, gaps: gaps, elements: sample)
                .debounce(for: debounceInterval, clock: clock)
        )
    }
}

/// The `cancellationCeasesEmission` property: consume `sample` from a timed
/// source, cancel the consumer at half the total time, and ask whether it
/// stopped without virtual time passing and saw only a prefix.
///
/// Under `TestClock` a sleep that ignored cancellation showed up as a hang,
/// because nothing advanced the clock after the cancel. Virtual time keeps
/// advancing while anything is asleep, so such a sleep would be woken later
/// and the consumer would finish — the instant it finishes at is what tells
/// the two apart. `sourceClock` lets a test hand the source a clock that
/// does ignore cancellation, to show the law notices.
func cancellationCeasesEmission<Element: Equatable & Sendable, SourceClock: Clock & Sendable>(
    of sample: [Element],
    sourceClock: @escaping @Sendable (VirtualClock) -> SourceClock
) async throws -> Bool where SourceClock.Duration == Swift.Duration {
    let gaps = derivedGaps(count: sample.count)
    let half = gaps.reduce(Swift.Duration.zero, +) / 2
    let (seen, stoppedPromptly) = try await runInVirtualTime { clock in
        let source = TimedSource(clock: sourceClock(clock), gaps: gaps, elements: sample)
        let consumer = Task { () -> [Element] in
            var seen: [Element] = []
            do {
                for try await element in source { seen.append(element) }
            } catch {
                // CancellationError propagating from clock.sleep is the
                // expected exit path.
            }
            return seen
        }
        try await clock.sleep(for: half)
        consumer.cancel()
        let cancelledAt = clock.now
        let seen = await consumer.value
        return (seen, clock.now == cancelledAt)
    }
    return stoppedPromptly && seen == Array(sample.prefix(seen.count))
}

/// The run's own failure — a deadlock or a passed horizon — when there was
/// one, so the counterexample says why rather than only that.
private func thrownSuffix(_ error: ErrorBox?) -> String {
    error.map { " (\($0.message))" } ?? ""
}

func isSubsequence<Element: Equatable>(_ candidate: [Element], of source: [Element]) -> Bool {
    var sourceIterator = source.makeIterator()
    outer: for element in candidate {
        while let next = sourceIterator.next() {
            if next == element { continue outer }
        }
        return false
    }
    return true
}

// MARK: - Laws

private func checkDebounceSubsequence<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "TimedAsyncSequence.debounceOutputIsSubsequenceOfInput",
        generator: generator,
        options: options,
        property: { sample in
            isSubsequence(try await debouncedOutput(of: sample), of: sample)
        },
        formatCounterexample: { sample, error in
            "source = \(sample); debounce emitted elements that are not a "
                + "subsequence of the input" + thrownSuffix(error)
        }
    )
}

private func checkDebounceFinalElement<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "TimedAsyncSequence.debounceEmitsFinalElement",
        generator: generator,
        options: options,
        property: { sample in
            guard sample.isEmpty == false else { return true }
            return try await debouncedOutput(of: sample).last == sample.last
        },
        formatCounterexample: { sample, error in
            "source = \(sample); debounce did not surface the final element "
                + "after quiescence" + thrownSuffix(error)
        }
    )
}

private func checkDebounceDeterminism<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "TimedAsyncSequence.debounceIsDeterministicUnderTestClock",
        generator: generator,
        options: options,
        property: { sample in
            // The Phase 4 headline: with the clock injected and time moved
            // only at quiescence, the async pipeline is a pure function of
            // (elements, gaps, interval).
            let first = try await debouncedOutput(of: sample)
            let second = try await debouncedOutput(of: sample)
            return first == second
        },
        formatCounterexample: { sample, error in
            "source = \(sample); two debounce runs under fresh virtual clocks "
                + "produced different outputs" + thrownSuffix(error)
        }
    )
}

private func checkCancellationCeasesEmission<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "TimedAsyncSequence.cancellationCeasesEmission",
        generator: generator,
        options: options,
        property: { sample in
            try await cancellationCeasesEmission(of: sample) { $0 }
        },
        formatCounterexample: { sample, error in
            "source = \(sample); cancelled consumer observed non-prefix "
                + "elements or needed virtual time to stop" + thrownSuffix(error)
        }
    )
}

/// Checks the virtual-time `AsyncSequence` laws over values drawn from `generator`.
///
/// Each sample is a source array whose elements arrive after position-derived gaps on a
/// `VirtualClock`, so no trial waits on wall-clock time. The laws cover `debounce`'s
/// output, its final element, its determinism under an injected clock, and prompt
/// cancellation.
///
/// - Parameters:
///   - generator: The values to check the laws against.
///   - options: The budget, enforcement and suppressions for the run.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkTimedAsyncSequencePropertyLaws<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: [Element].Type = [Element].self,
    using generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkDebounceSubsequence(generator: generator, options: options),
            await checkDebounceFinalElement(generator: generator, options: options),
            await checkDebounceDeterminism(generator: generator, options: options),
            await checkCancellationCeasesEmission(generator: generator, options: options),
        ]
    }
}
