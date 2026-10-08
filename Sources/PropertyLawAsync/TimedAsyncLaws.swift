import AsyncAlgorithms
import PropertyBased
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

extension LawIdentifier {
    public static func timedAsync(_ law: TimedAsyncLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "TimedAsyncSequence", lawName: law.rawValue)
    }
}

@discardableResult
public func checkTimedAsyncSequencePropertyLaws<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: [Element].Type = [Element].self,
    using generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkDebounceSubsequence(generator: generator, options: options),
            await checkDebounceFinalElement(generator: generator, options: options),
            await checkDebounceDeterminism(generator: generator, options: options),
            await checkCancellationCeasesEmission(generator: generator, options: options)
        ]
    }
}

// MARK: - Timed source

/// A finite async sequence that yields each element after a virtual-time
/// gap on the injected clock. The gaps are the *entire* time behavior —
/// nothing here touches a wall clock.
struct TimedSource<Element: Sendable, ClockType: Clock & Sendable>: AsyncSequence, Sendable
where ClockType.Duration == Swift.Duration {
    let clock: ClockType
    let gaps: [Swift.Duration]
    let elements: [Element]

    struct AsyncIterator: AsyncIteratorProtocol {
        let clock: ClockType
        let gaps: [Swift.Duration]
        let elements: [Element]
        var position = 0

        mutating func next() async throws -> Element? {
            guard position < elements.count else { return nil }
            try await clock.sleep(for: gaps[position], tolerance: nil)
            defer { position += 1 }
            return elements[position]
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(clock: clock, gaps: gaps, elements: elements)
    }
}

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
