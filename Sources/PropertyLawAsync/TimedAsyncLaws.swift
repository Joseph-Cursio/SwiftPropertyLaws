import AsyncAlgorithms
import Clocks
import PropertyBased
import PropertyLawKit

/// Phase 4 of the collections/async workplan — the virtual-time laws.
///
/// Time-parameterized combinators (`debounce` here; `throttle` when its API
/// stabilizes upstream) are nondeterministic against wall clocks but fully
/// deterministic against an injected `TestClock`: virtual time advances only
/// when the law says so, which is the whole trick. The generated carrier is
/// again the source array; per-element *gaps* and the debounce *interval*
/// are derived deterministically from position and count, so a seeded run
/// replays exactly.
///
/// - `debounceOutputIsSubsequenceOfInput` — debounce may drop, never
///   invent or reorder: output is a (not necessarily contiguous)
///   subsequence of input.
/// - `debounceEmitsFinalElement` — the last input element always surfaces
///   once quiescence passes (non-empty input).
/// - `debounceIsDeterministicUnderTestClock` — two runs over fresh
///   `TestClock`s produce identical output. This is the load-bearing law
///   for the workplan's effect story: *async + injected clock ⇒
///   deterministic*, the refinement SwiftEffectInference's annotation
///   route will name.
/// - `cancellationCeasesEmission` — cancelling the consuming task stops
///   the pipeline promptly (cancellation propagates through
///   `clock.sleep`), and everything observed before the cancel is a
///   prefix of the source.
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

/// Run the sample through debounce under a fresh TestClock, advancing
/// virtual time far past the last event plus quiescence.
func debouncedOutput<Element: Sendable>(of sample: [Element]) async throws -> [Element] {
    let clock = TestClock()
    let source = TimedSource(clock: clock, gaps: derivedGaps(count: sample.count), elements: sample)
    let consumer = Task {
        try await collect(source.debounce(for: debounceInterval, clock: clock))
    }
    let total = derivedGaps(count: sample.count).reduce(Swift.Duration.zero, +)
    await clock.advance(by: total + debounceInterval + debounceInterval)
    return try await consumer.value
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
        formatCounterexample: { sample, _ in
            "source = \(sample); debounce emitted elements that are not a "
                + "subsequence of the input"
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
        formatCounterexample: { sample, _ in
            "source = \(sample); debounce did not surface the final element "
                + "after quiescence"
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
            // The Phase 4 headline: with the clock injected, the async
            // pipeline is a pure function of (elements, gaps, interval).
            let first = try await debouncedOutput(of: sample)
            let second = try await debouncedOutput(of: sample)
            return first == second
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); two debounce runs under fresh TestClocks "
                + "produced different outputs"
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
            let clock = TestClock()
            let source = TimedSource(
                clock: clock,
                gaps: derivedGaps(count: sample.count),
                elements: sample
            )
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
            let total = derivedGaps(count: sample.count).reduce(Swift.Duration.zero, +)
            let half = total / 2
            await clock.advance(by: half)
            consumer.cancel()
            // The task must complete (cancellation propagates through the
            // clock sleep — a hang here is the failure), and what it saw
            // must be a prefix of the source.
            let seen = await consumer.value
            return seen == Array(sample.prefix(seen.count))
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); cancelled consumer observed non-prefix "
                + "elements or failed to stop"
        }
    )
}
