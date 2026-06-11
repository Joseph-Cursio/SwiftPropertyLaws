import PropertyBased

/// Run `Sequence` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` first runs the inherited `IteratorProtocol` suite per
/// PRD §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Sequence laws (returned in this order after the inherited suite, when run):
/// - `underestimatedCountLowerBound` (Strict) — the iterator yields at least
///   `underestimatedCount` elements.
/// - `multiPassConsistency` (Conventional) — two fresh iterators yield the
///   same elements in the same order. Suppressed by `passing: .singlePass`.
/// - `makeIteratorIndependence` (Conventional) — calling `makeIterator()`
///   does not perturb prior iterators or the sequence's observable state.
///   Suppressed by `passing: .singlePass`.
///
/// Near-miss tracking for `underestimatedCountLowerBound` is intentionally
/// not wired (deferred). The PRD §4.6 criterion is "iterators that yielded a
/// count off-by-one from `underestimatedCount`" — well-defined on the
/// failing path. But every `Collection` (the common case) reports
/// `underestimatedCount == count`, so the passing-side "tight margin"
/// reading is vacuous, and the kit's existing planted-bug fixture
/// (`LyingUnderestimatedCount`) produces diffs of magnitude 3–5, not
/// off-by-one. Wiring this cleanly waits on either a real-world report or a
/// targeted planted-bug fixture; until then the field stays nil per the PRD
/// §4.6 "this law doesn't track" semantic.
@discardableResult
public func checkSequencePropertyLaws<Value: Sequence & Sendable, Shrinker: SendableSequenceType>(
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
            try await checkIteratorProtocolPropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(await checkUnderestimated(generator: generator, options: options))
    if sequenceOptions.passing == .multiPass {
        results.append(await checkMultiPass(generator: generator, options: options))
        results.append(await checkIndependence(generator: generator, options: options))
    }
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkUnderestimated<S: Sequence & Sendable, Sh: SendableSequenceType>(
    generator: Generator<S, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await PerLawDriver.run(
        protocolLaw: "Sequence.underestimatedCountLowerBound",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in underestimatedCounterexample(for: sample) == nil },
            formatCounterexample: { sample, _ in
                underestimatedCounterexample(for: sample) ?? "<no counterexample>"
            }
        )
    )
}

private func checkMultiPass<S: Sequence & Sendable, Sh: SendableSequenceType>(
    generator: Generator<S, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await PerLawDriver.run(
        protocolLaw: "Sequence.multiPassConsistency",
        tier: .conventional,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in multiPassCounterexample(for: sample) == nil },
            formatCounterexample: { sample, _ in
                multiPassCounterexample(for: sample) ?? "<no counterexample>"
            }
        )
    )
}

private func checkIndependence<S: Sequence & Sendable, Sh: SendableSequenceType>(
    generator: Generator<S, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where S.Element: Equatable & Sendable {
    await PerLawDriver.run(
        protocolLaw: "Sequence.makeIteratorIndependence",
        tier: .conventional,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in independenceCounterexample(for: sample) == nil },
            formatCounterexample: { sample, _ in
                independenceCounterexample(for: sample) ?? "<no counterexample>"
            }
        )
    )
}

private func underestimatedCounterexample<S: Sequence>(for sample: S) -> String? {
    let underestimated = sample.underestimatedCount
    let cap = iterationCap(for: sample, floor: underestimated)
    var iterator = sample.makeIterator()
    var pulled = 0
    while pulled < cap, iterator.next() != nil { pulled += 1 }
    if pulled < underestimated {
        return "sequence \(sample) reported underestimatedCount = \(underestimated) "
            + "but iterator yielded only \(pulled) elements before returning nil"
    }
    return nil
}

private func multiPassCounterexample<S: Sequence>(for sample: S) -> String?
where S.Element: Equatable {
    let cap = iterationCap(for: sample, floor: sample.underestimatedCount)
    let pass1 = collect(sample, cap: cap)
    let pass2 = collect(sample, cap: cap)
    if pass1 != pass2 {
        return "sequence \(sample) yielded different elements on two fresh iterators "
            + "(pass1 = \(pass1.prefix(8))…, pass2 = \(pass2.prefix(8))…)"
    }
    return nil
}

private func independenceCounterexample<S: Sequence>(for sample: S) -> String?
where S.Element: Equatable {
    let cap = iterationCap(for: sample, floor: sample.underestimatedCount)

    let baseline = collect(sample, cap: cap)
    let half = baseline.count / 2

    var iteratorA = sample.makeIterator()
    var prefixA: [S.Element] = []
    for _ in 0..<half {
        guard let element = iteratorA.next() else { break }
        prefixA.append(element)
    }
    var iteratorB = sample.makeIterator()
    var fullB: [S.Element] = []
    var pulled = 0
    while pulled < cap, let element = iteratorB.next() {
        fullB.append(element)
        pulled += 1
    }
    var suffixA: [S.Element] = []
    var pulledA = prefixA.count
    while pulledA < cap, let element = iteratorA.next() {
        suffixA.append(element)
        pulledA += 1
    }
    let interleavedA = prefixA + suffixA
    if interleavedA != baseline {
        return "interleaving makeIterator() perturbed iterator A on \(sample): "
            + "baseline = \(baseline.prefix(8))…, interleavedA = \(interleavedA.prefix(8))…"
    }
    if fullB != baseline {
        return "second iterator on \(sample) yielded different elements from baseline: "
            + "baseline = \(baseline.prefix(8))…, fullB = \(fullB.prefix(8))…"
    }
    return nil
}

private func collect<S: Sequence>(_ sample: S, cap: Int) -> [S.Element] {
    var iterator = sample.makeIterator()
    var collected: [S.Element] = []
    var pulled = 0
    while pulled < cap, let element = iterator.next() {
        collected.append(element)
        pulled += 1
    }
    return collected
}

/// Cap on per-trial iterator pulls. The floor protects against runaway
/// iterators that under-report their `underestimatedCount`.
private func iterationCap<S: Sequence>(for sample: S, floor: Int) -> Int {
    let underestimated = sample.underestimatedCount
    let bumped = Swift.max(underestimated, floor) &* 100
    return Swift.max(10_000, bumped)
}
