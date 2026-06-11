import PropertyBased

/// Run `Collection` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` first runs the inherited `Sequence` suite (which
/// itself chains the `IteratorProtocol` suite). Pass `.ownOnly` to skip
/// inherited laws.
///
/// Collection laws:
/// - `countConsistency` (Strict) — `count` matches the number of iterated
///   elements.
/// - `indexValidity` (Strict) — every index reachable by `index(after:)` from
///   `startIndex` is `< endIndex`, dereferences without crash, and matches
///   the corresponding element from sequence iteration.
/// - `nonMutation` (Conventional) — iterating does not perturb subsequent
///   passes. Trivially passes for value-type collections; meaningful for
///   reference-type collections that hold shared mutable state (relaxed for
///   lazy / view-like wrappers — see PRD §4.3).
///
/// **Near-miss tracking (M5).** `countConsistency` records "off-by-one"
/// violations (the most common bug class) on the failing trial so the
/// reviewer sees the diff magnitude in `CheckResult.nearMisses`.
@discardableResult
public func checkCollectionPropertyLaws<Value: Collection & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sequenceOptions: SequenceLawOptions = SequenceLawOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult]
where Value.Element: Equatable & Sendable {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkSequencePropertyLaws(
                    for: type,
                    using: generator,
                    options: $0,
                    sequenceOptions: sequenceOptions
                )
            })
        }
        results.append(contentsOf: [
            await checkCount(generator: generator, options: options),
            await checkIndexValidity(generator: generator, options: options),
            await checkNonMutation(generator: generator, options: options)
        ])
        return results
    }
}

private func checkCount<C: Collection & Sendable, Sh: SendableSequenceType>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    let collector = NearMissCollector()
    return await runUnaryLaw(
        "Collection.countConsistency",
        generator: generator,
        options: options,
        observation: PerLawDriver.Observation(nearMissCollector: collector),
        property: { sample in
            let detail = countDetail(for: sample)
            if let detail, detail.isOffByOne {
                collector.record(
                    "off-by-one: count = \(detail.reportedCount), "
                        + "iterated = \(detail.iteratedCount) on \(sample)"
                )
            }
            return detail == nil
        },
        formatCounterexample: { sample, _ in
            countDetail(for: sample)?.message ?? "<no counterexample>"
        }
    )
}

private func checkIndexValidity<C: Collection & Sendable, Sh: SendableSequenceType>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "Collection.indexValidity",
        generator: generator,
        options: options,
        property: { sample in indexValidityCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            indexValidityCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

private func checkNonMutation<C: Collection & Sendable, Sh: SendableSequenceType>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "Collection.nonMutation",
        tier: .conventional,
        generator: generator,
        options: options,
        property: { sample in nonMutationCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            nonMutationCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

/// Detail record for a `count` mismatch — `nil` when the law holds. Returned
/// from a single helper so the property closure, the formatter, and the
/// near-miss recorder all see a consistent view.
private struct CountMismatchDetail {
    let reportedCount: Int
    let iteratedCount: Int

    var isOffByOne: Bool {
        Swift.abs(reportedCount - iteratedCount) == 1
    }

    var message: String {
        "collection reported count = \(reportedCount) "
            + "but iteration yielded \(iteratedCount) elements"
    }
}

private func countDetail<C: Collection>(for sample: C) -> CountMismatchDetail? {
    let reportedCount = sample.count
    let cap = Swift.max(reportedCount &+ 1, 10_000)
    let iteratedCount = manualIteratedCount(of: sample, cap: cap)
    if reportedCount == iteratedCount { return nil }
    return CountMismatchDetail(
        reportedCount: reportedCount,
        iteratedCount: iteratedCount
    )
}

private func indexValidityCounterexample<C: Collection>(for sample: C) -> String?
where C.Element: Equatable {
    let iterated = manualCollect(from: sample)
    var index = sample.startIndex
    var subscripted: [C.Element] = []
    let cap = iterated.count &+ 1
    var steps = 0
    while index != sample.endIndex {
        if steps > cap {
            return "collection \(sample) index walk exceeded \(cap) steps without "
                + "reaching endIndex — index(after:) likely doesn't advance"
        }
        subscripted.append(sample[index])
        index = sample.index(after: index)
        steps += 1
    }
    if subscripted != iterated {
        return "collection \(sample) sequence iteration yielded \(iterated.prefix(8))… "
            + "but index walk yielded \(subscripted.prefix(8))…"
    }
    return nil
}

// Iterating over a value-type collection produces a copy and cannot mutate the
// original observable state through generic dispatch — this check is
// structurally unviolable for those. It's meaningful for reference-type
// collections that hold shared state. Comparable to Equatable.negationConsistency:
// kept as defensive coverage, conventional tier so it doesn't fail-CI on the
// common no-op case.
private func nonMutationCounterexample<C: Collection>(for sample: C) -> String?
where C.Element: Equatable {
    let pass1 = manualCollect(from: sample)
    let pass2 = manualCollect(from: sample)
    if pass1 != pass2 {
        return "iterating collection \(sample) appears to perturb its observable state: "
            + "pass1 = \(pass1.prefix(8))…, pass2 = \(pass2.prefix(8))…"
    }
    return nil
}

/// Iterate via Sequence's `makeIterator()` until `nil`, capped to defend
/// against runaway iterators. Avoids `Array(c)` which traps when `c.count`
/// disagrees with iteration — the precise condition `countConsistency`
/// exists to catch.
private func manualCollect<S: Sequence>(from sample: S, cap: Int = 100_000) -> [S.Element] {
    var iterator = sample.makeIterator()
    var collected: [S.Element] = []
    var pulled = 0
    while pulled < cap, let element = iterator.next() {
        collected.append(element)
        pulled += 1
    }
    return collected
}

private func manualIteratedCount<S: Sequence>(of sample: S, cap: Int) -> Int {
    var iterator = sample.makeIterator()
    var count = 0
    while count < cap, iterator.next() != nil { count += 1 }
    return count
}
