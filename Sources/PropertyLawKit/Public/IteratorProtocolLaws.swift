import PropertyBased

/// Run `IteratorProtocol` protocol laws (PRD §4.3).
///
/// Parameterized over the host `Sequence` rather than the iterator itself: the
/// check makes a fresh iterator inside each trial via `makeIterator()`. This
/// keeps the API Sendable-clean (most iterators are reference-shaped and not
/// Sendable, but the sequence value is) and matches how iterators are used in
/// idiomatic Swift code.
///
/// Laws (both Conventional tier — see PRD §4.3 IteratorProtocol):
/// - **Termination stability**: once `next()` returns `nil`, subsequent calls
///   also return `nil` (the iterator stays exhausted).
/// - **Single-pass yield**: an iterator over a finite sequence terminates
///   within a generous cap of its source's `underestimatedCount`. An iterator
///   that loops forever or resets after `nil` triggers this check.
@discardableResult
public func checkIteratorProtocolPropertyLaws<S: Sequence & Sendable, Sh: SendableSequenceType>(
    for type: S.Type = S.self,
    using generator: Generator<S, Sh>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where S.Element: Equatable & Sendable {
    try await runPropertyLawSuite(options: options) {
        [
            await runUnaryLaw(
                "IteratorProtocol.terminationStability",
                tier: .conventional,
                generator: generator,
                options: options,
                property: { sample in iteratorTerminationCounterexample(for: sample) == nil },
                formatCounterexample: { sample, _ in
                    iteratorTerminationCounterexample(for: sample) ?? "<no counterexample>"
                }
            ),
            await runUnaryLaw(
                "IteratorProtocol.singlePassYield",
                tier: .conventional,
                generator: generator,
                options: options,
                property: { sample in iteratorSinglePassCounterexample(for: sample) == nil },
                formatCounterexample: { sample, _ in
                    iteratorSinglePassCounterexample(for: sample) ?? "<no counterexample>"
                }
            )
        ]
    }
}

/// Returns the counterexample string when termination stability is violated,
/// else `nil`. Property closure and formatter both call this — on failure
/// the iteration runs twice, which is fine (one trial path).
private func iteratorTerminationCounterexample<S: Sequence>(
    for sample: S
) -> String? {
    var iterator = sample.makeIterator()
    let cap = iterationCap(for: sample)
    var pulled = 0
    while pulled < cap, iterator.next() != nil { pulled += 1 }
    if pulled == cap {
        // Couldn't observe termination — that's single-pass-yield's problem.
        return nil
    }
    let secondNil = iterator.next()
    let thirdNil = iterator.next()
    if secondNil != nil || thirdNil != nil {
        return "iterator over \(sample) returned nil then yielded another element on a "
            + "subsequent call (secondNil=\(String(describing: secondNil)), "
            + "thirdNil=\(String(describing: thirdNil)))"
    }
    return nil
}

private func iteratorSinglePassCounterexample<S: Sequence>(
    for sample: S
) -> String? {
    var iterator = sample.makeIterator()
    let cap = iterationCap(for: sample)
    var pulled = 0
    while pulled < cap, iterator.next() != nil { pulled += 1 }
    if pulled == cap {
        return "iterator over \(sample) yielded \(pulled) elements without terminating "
            + "(cap based on underestimatedCount = \(sample.underestimatedCount)); "
            + "suspected infinite loop or post-`nil` reset"
    }
    return nil
}

/// Generous upper bound on next()-call count per trial. Allows iterators that
/// produce more than `underestimatedCount` elements (the bound is a *lower*
/// bound by Sequence's contract) but rejects those that run away.
private func iterationCap<S: Sequence>(for sample: S) -> Int {
    let underestimated = sample.underestimatedCount
    return Swift.max(10_000, underestimated &* 100)
}
