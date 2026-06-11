import PropertyBased

/// Run `BidirectionalCollection` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` first runs the inherited `Collection` suite (which
/// itself chains the `Sequence` and `IteratorProtocol` suites). Pass
/// `.ownOnly` to skip inherited laws.
///
/// BidirectionalCollection laws (all Strict):
/// - `indexBeforeAfterRoundTrip` — for any non-end index `i`,
///   `index(before: index(after: i)) == i`.
/// - `indexAfterBeforeRoundTrip` — for any non-start index `j`,
///   `index(after: index(before: j)) == j`.
/// - `reverseTraversalConsistency` — walking from `endIndex` via
///   `index(before:)` to `startIndex` yields the elements in the reverse of
///   forward iteration.
@discardableResult
public func checkBidirectionalCollectionPropertyLaws<
    Value: BidirectionalCollection & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sequenceOptions: SequenceLawOptions = SequenceLawOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult]
where Value.Element: Equatable & Sendable {
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
            try await checkCollectionPropertyLaws(
                for: type,
                using: generator,
                options: $0,
                sequenceOptions: sequenceOptions
            )
        })
    }
    results.append(contentsOf: [
        await checkIndexBeforeAfter(generator: generator, options: options),
        await checkIndexAfterBefore(generator: generator, options: options),
        await checkReverseTraversal(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkIndexBeforeAfter<
    C: BidirectionalCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "BidirectionalCollection.indexBeforeAfterRoundTrip",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in indexBeforeAfterCounterexample(for: sample) == nil },
            formatCounterexample: { sample, _ in
                indexBeforeAfterCounterexample(for: sample) ?? "<no counterexample>"
            }
        )
    )
}

private func checkIndexAfterBefore<
    C: BidirectionalCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "BidirectionalCollection.indexAfterBeforeRoundTrip",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in indexAfterBeforeCounterexample(for: sample) == nil },
            formatCounterexample: { sample, _ in
                indexAfterBeforeCounterexample(for: sample) ?? "<no counterexample>"
            }
        )
    )
}

private func checkReverseTraversal<
    C: BidirectionalCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "BidirectionalCollection.reverseTraversalConsistency",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in reverseTraversalCounterexample(for: sample) == nil },
            formatCounterexample: { sample, _ in
                reverseTraversalCounterexample(for: sample) ?? "<no counterexample>"
            }
        )
    )
}

private func indexBeforeAfterCounterexample<C: BidirectionalCollection>(
    for sample: C
) -> String? {
    var index = sample.startIndex
    let cap = walkCap(for: sample)
    var steps = 0
    while index != sample.endIndex {
        if steps > cap {
            return "forward walk on \(sample) exceeded \(cap) steps without "
                + "reaching endIndex — index(after:) likely doesn't advance"
        }
        let advanced = sample.index(after: index)
        let retreated = sample.index(before: advanced)
        if retreated != index {
            return "index(before: index(after: i)) on \(sample) yielded "
                + "different index at i = \(index)"
        }
        index = advanced
        steps += 1
    }
    return nil
}

private func indexAfterBeforeCounterexample<C: BidirectionalCollection>(
    for sample: C
) -> String? {
    if sample.startIndex == sample.endIndex { return nil }
    var index = sample.endIndex
    let cap = walkCap(for: sample)
    var steps = 0
    while index != sample.startIndex {
        if steps > cap {
            return "reverse walk on \(sample) exceeded \(cap) steps without "
                + "reaching startIndex — index(before:) likely doesn't move"
        }
        let retreated = sample.index(before: index)
        let advanced = sample.index(after: retreated)
        if advanced != index {
            return "index(after: index(before: j)) on \(sample) yielded "
                + "different index at j = \(index)"
        }
        index = retreated
        steps += 1
    }
    return nil
}

/// Verifies that walking via `index(before:)` from `endIndex` to
/// `startIndex` yields the *reverse* of the forward index sequence. We
/// compare indices rather than subscript-fetched elements: a broken
/// subscript is the domain of `Collection.indexValidity`, and subscripting
/// from a buggy `index(before:)` (e.g. one that returns `endIndex` itself
/// or an out-of-range value) can trap before we ever check anything.
private func reverseTraversalCounterexample<C: BidirectionalCollection>(
    for sample: C
) -> String? {
    var forwardIndices: [C.Index] = []
    var fIdx = sample.startIndex
    let cap = walkCap(for: sample)
    var fSteps = 0
    while fIdx != sample.endIndex {
        if fSteps > cap {
            return "forward walk on \(sample) exceeded \(cap) steps — "
                + "index(after:) likely doesn't advance"
        }
        forwardIndices.append(fIdx)
        fIdx = sample.index(after: fIdx)
        fSteps += 1
    }
    var index = sample.endIndex
    var bSteps = 0
    var expectedPosition = forwardIndices.count
    while index != sample.startIndex {
        if bSteps > cap {
            return "reverse walk on \(sample) exceeded \(cap) steps — "
                + "index(before:) likely doesn't move"
        }
        index = sample.index(before: index)
        expectedPosition -= 1
        if expectedPosition < 0 {
            return "reverse walk on \(sample) overshot startIndex"
        }
        let expected = forwardIndices[expectedPosition]
        if index != expected {
            return "reverse walk on \(sample): index(before:) at step "
                + "\(bSteps) yielded \(index), expected \(expected)"
        }
        bSteps += 1
    }
    return nil
}

/// Cap on per-trial index walks. Defends against runaway `index(after:)` /
/// `index(before:)` implementations that don't make progress — same shape
/// as `CollectionLaws.indexValidity`'s cap.
private func walkCap<C: Collection>(for sample: C) -> Int {
    let reported = sample.count
    return Swift.max(reported &+ 1, 10_000)
}
